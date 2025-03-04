/*
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package chaos_test

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/fis"
	fistypes "github.com/aws/aws-sdk-go-v2/service/fis/types"
	awsiam "github.com/aws/aws-sdk-go-v2/service/iam"
	iamtypes "github.com/aws/aws-sdk-go-v2/service/iam/types"
	"github.com/google/uuid"
	"github.com/samber/lo"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"sigs.k8s.io/controller-runtime/pkg/client"

	awserrors "github.com/aws/karpenter-provider-aws/pkg/errors"

	karpv1 "sigs.k8s.io/karpenter/pkg/apis/v1"
	coretest "sigs.k8s.io/karpenter/pkg/test"

	awsenv "github.com/aws/karpenter-provider-aws/test/pkg/environment/aws"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var fisRoleName string
var fisRoleArn string
var customPolicyArn string
var _ = Describe("ZonalFailure", func() {
	BeforeEach(func() {
		setupRoles(env)
	})
	AfterEach(func() {
		cleanupRoles(env)
	})

	DescribeTable("should recover from AZ failures with different failure rates",
		func(failureRate string, appLabel string, description string) {
			By(fmt.Sprintf("Creating a multi-AZ deployment with multiple replicas for %s test", description))
			nodePool = coretest.ReplaceRequirements(nodePool, karpv1.NodeSelectorRequirementWithMinValues{
				NodeSelectorRequirement: corev1.NodeSelectorRequirement{
					Key:      karpv1.CapacityTypeLabelKey,
					Operator: corev1.NodeSelectorOpIn,
					Values:   []string{karpv1.CapacityTypeOnDemand},
				},
			})
			nodePool.Spec.Disruption.ConsolidationPolicy = karpv1.ConsolidationPolicyWhenEmptyOrUnderutilized
			nodePool.Spec.Disruption.ConsolidateAfter = karpv1.MustParseNillableDuration("30s")

			numPods := 15
			dep := coretest.Deployment(coretest.DeploymentOptions{
				Replicas: int32(numPods),
				PodOptions: coretest.PodOptions{
					ObjectMeta: metav1.ObjectMeta{
						Labels: map[string]string{"app": appLabel},
					},
					TerminationGracePeriodSeconds: lo.ToPtr(int64(0)),
					TopologySpreadConstraints: []corev1.TopologySpreadConstraint{
						{
							MaxSkew:           1,
							TopologyKey:       "topology.kubernetes.io/zone",
							WhenUnsatisfiable: corev1.DoNotSchedule,
							LabelSelector: &metav1.LabelSelector{
								MatchLabels: map[string]string{"app": appLabel},
							},
						},
					},
				},
			})
			selector := labels.SelectorFromSet(dep.Spec.Selector.MatchLabels)

			env.ExpectCreated(nodeClass, nodePool, dep)
			env.EventuallyExpectHealthyPodCount(selector, numPods)

			ctx, cancel := context.WithCancel(env.Context)
			defer cancel()

			startNodeCountMonitor(ctx, env.Client)

			// find AZ with most nodes
			nodesByAZ := make(map[string][]*corev1.Node)
			var targetAZ string
			var maxNodes int
			var instances []ec2types.Instance
			nodeList := &corev1.NodeList{}
			Expect(env.Client.List(ctx, nodeList, client.HasLabels{coretest.DiscoveryLabel})).To(Succeed())

			for i := range nodeList.Items {
				node := &nodeList.Items[i]
				az := node.Labels[corev1.LabelTopologyZone]
				if az == "" {
					continue
				}
				nodesByAZ[az] = append(nodesByAZ[az], node)
				if len(nodesByAZ[az]) > maxNodes {
					maxNodes = len(nodesByAZ[az])
					targetAZ = az
				}
			}

			Expect(len(nodesByAZ)).To(BeNumerically(">", 1), "Expected nodes in multiple AZs")

			By(fmt.Sprintf("Simulating %s with %d nodes (%s%% failure rate)",
				description, maxNodes, failureRate))

			for _, node := range nodesByAZ[targetAZ] {
				instance := env.GetInstance(node.Name)
				instances = append(instances, instance)
			}

			By(fmt.Sprintf("Creating experiment template for AZ %s", targetAZ))
			templateId := createExperimentTemplate(ctx, env, targetAZ, instances, failureRate)

			By("Starting the experiment")
			experiment := startExperiment(ctx, env, templateId)

			By(fmt.Sprintf("Waiting for the %s experiment to complete", description))
			Eventually(func(g Gomega) {
				select {
				case <-ctx.Done():
					By("Chaos test timeout reached, skipping experiment status check")
					return
				default:
					// Check if pods have already been rescheduled and are healthy
					// If so, we can exit early without waiting for experiment completion
					pods := env.Monitor.RunningPods(selector)
					if len(pods) == numPods {
						By("All pods have been successfully rescheduled and are healthy, continuing test")
						return
					}
					exp, err := env.FISAPI.GetExperiment(ctx, &fis.GetExperimentInput{
						Id: experiment.Id,
					})
					g.Expect(err).NotTo(HaveOccurred())
					g.Expect(exp.Experiment.State.Status).To(Or(
						Equal(fistypes.ExperimentStatusCompleted),
						Equal(fistypes.ExperimentStatusStopped),
					))
					g.Expect(exp.Experiment.State.Status).To(Not(Equal(fistypes.ExperimentActionStatusFailed)))
				}
			}, 10*time.Minute, 30*time.Second).Should(Succeed())

			By(fmt.Sprintf("Verifying system recovery from %s", description))
			env.EventuallyExpectHealthyPodCountWithTimeout(5*time.Minute, selector, numPods)

			By("Cleaning up test resources")
			env.ExpectDeleted(dep)
			env.ExpectExperimentTemplateDeleted(templateId)

			Eventually(func(g Gomega) {
				nodeList := &corev1.NodeList{}
				g.Expect(env.Client.List(env.Context, nodeList, client.HasLabels{coretest.DiscoveryLabel})).To(Succeed())
				for _, node := range nodeList.Items {
					g.Expect(env.Client.Delete(env.Context, &node)).To(Succeed())
				}
				nodeClaimList := &karpv1.NodeClaimList{}
				g.Expect(env.Client.List(env.Context, nodeClaimList, client.HasLabels{coretest.DiscoveryLabel})).To(Succeed())
				for _, nodeClaim := range nodeClaimList.Items {
					g.Expect(env.Client.Delete(env.Context, &nodeClaim)).To(Succeed())
				}

				g.Eventually(func() int {
					tempNodeList := &corev1.NodeList{}
					g.Expect(env.Client.List(env.Context, tempNodeList, client.HasLabels{coretest.DiscoveryLabel})).To(Succeed())
					return len(tempNodeList.Items)
				}, 2*time.Minute, 10*time.Second).Should(BeZero())

				describeInstancesOutput, err := env.EC2API.DescribeInstances(env.Context, &ec2.DescribeInstancesInput{
					Filters: []ec2types.Filter{
						{
							Name:   aws.String(fmt.Sprintf("tag:%s", coretest.DiscoveryLabel)),
							Values: []string{env.ClusterName},
						},
					},
				})
				g.Expect(err).NotTo(HaveOccurred())

				var instanceIDs []string
				for _, reservation := range describeInstancesOutput.Reservations {
					for _, instance := range reservation.Instances {
						if instance.InstanceId != nil {
							instanceIDs = append(instanceIDs, *instance.InstanceId)
						}
					}
				}

				if len(instanceIDs) > 0 {
					fmt.Printf("Terminating %d remaining EC2 instances\n", len(instanceIDs))
					_, err := env.EC2API.TerminateInstances(env.Context, &ec2.TerminateInstancesInput{
						InstanceIds: instanceIDs,
					})
					g.Expect(awserrors.IgnoreNotFound(err)).NotTo(HaveOccurred())
				}
			}, 5*time.Minute).Should(Succeed())
		},
		Entry("complete failure", "100", "complete-failure-app", "complete AZ failure"),
		Entry("moderate failure", "50", "moderate-failure-app", "moderate AZ failures"),
		Entry("minor failure", "25", "minor-failure-app", "minor AZ failures"),
	)
})

func createExperimentTemplate(ctx context.Context, env *awsenv.Environment, targetAZ string, instances []ec2types.Instance, failurePercentage string) string {
	// Filter instances to only include those in the target AZ
	var targetInstances []string
	for _, instance := range instances {
		if instance.InstanceId != nil && instance.Placement != nil && instance.Placement.AvailabilityZone != nil {
			targetInstances = append(targetInstances, *instance.InstanceId)
		}
	}

	subnetARNs := getSubnetsInAZ(ctx, env, targetAZ)
	By(fmt.Sprintf("Found %d subnets in AZ %s", len(subnetARNs), targetAZ))

	template := &fis.CreateExperimentTemplateInput{
		Actions: map[string]fistypes.CreateExperimentTemplateActionInput{
			"stop-instances": {
				ActionId: aws.String("aws:ec2:stop-instances"),
				Parameters: map[string]string{
					"startInstancesAfterDuration": "PT5M", // Start instances after 5 minutes
				},
				Targets: map[string]string{
					"Instances": "target-instances",
				},
			},
			"ec2-capacity-error": {
				ActionId: aws.String("aws:ec2:api-insufficient-instance-capacity-error"),
				Parameters: map[string]string{
					"availabilityZoneIdentifiers": targetAZ,
					"duration":                    "PT5M",
					"percentage":                  failurePercentage,
				},
				Targets: map[string]string{
					"Roles": "target-roles",
				},
			},
			"disrupt-subnet": {
				ActionId: aws.String("aws:network:disrupt-connectivity"),
				Parameters: map[string]string{
					"duration": "PT5M",
					"scope":    "all",
				},
				Targets: map[string]string{
					"Subnets": "target-subnets",
				},
			},
		},
		Targets: map[string]fistypes.CreateExperimentTemplateTargetInput{
			"target-instances": {
				ResourceType:  aws.String("aws:ec2:instance"),
				SelectionMode: aws.String("ALL"),
				ResourceArns: lo.Map(targetInstances, func(id string, _ int) string {
					return fmt.Sprintf("arn:aws:ec2:%s:%s:instance/%s", env.Region, env.ExpectAccountID(), id)
				}),
			},
			"target-roles": {
				ResourceType:  aws.String("aws:iam:role"),
				SelectionMode: aws.String("ALL"),
				ResourceArns: []string{
					fmt.Sprintf("arn:aws:iam::%s:role/KarpenterNodeRole-%s", env.ExpectAccountID(), env.ClusterName),
				},
			},
			"target-subnets": {
				ResourceType:  aws.String("aws:ec2:subnet"),
				SelectionMode: aws.String("ALL"),
				ResourceArns:  subnetARNs,
			},
		},
		StopConditions: []fistypes.CreateExperimentTemplateStopConditionInput{
			{
				Source: aws.String("none"),
			},
		},
		RoleArn:     aws.String(fisRoleArn),
		Description: aws.String(fmt.Sprintf("Simulate AZ failure in %s", targetAZ)),
	}

	// Create experiment template
	experimentTemplate, err := env.FISAPI.CreateExperimentTemplate(ctx, template)
	Expect(err).NotTo(HaveOccurred())

	return *experimentTemplate.ExperimentTemplate.Id
}

func startExperiment(ctx context.Context, env *awsenv.Environment, templateId string) *fistypes.Experiment {
	experiment, err := env.FISAPI.StartExperiment(ctx, &fis.StartExperimentInput{
		ExperimentTemplateId: aws.String(templateId),
	})
	Expect(err).NotTo(HaveOccurred())
	return experiment.Experiment
}

func setupRoles(env *awsenv.Environment) {
	// First, check if the FIS service-linked role exists
	serviceRoleName := "AWSServiceRoleForFIS"
	_, err := env.IAMAPI.GetRole(env.Context, &awsiam.GetRoleInput{
		RoleName: aws.String(serviceRoleName),
	})

	if err != nil {
		// If the role doesn't exist, create it
		if awserrors.IsNotFound(err) {
			By("Creating FIS service-linked role")
			_, err = env.IAMAPI.CreateServiceLinkedRole(env.Context, &awsiam.CreateServiceLinkedRoleInput{
				AWSServiceName: aws.String("fis.amazonaws.com"),
				Description:    aws.String("Service-linked role for AWS Fault Injection Simulator"),
			})
			Expect(err).NotTo(HaveOccurred())

			// Wait for the role to be available
			By("Waiting for FIS service-linked role to be available")
			Eventually(func() error {
				_, err := env.IAMAPI.GetRole(env.Context, &awsiam.GetRoleInput{
					RoleName: aws.String(serviceRoleName),
				})
				return err
			}, 30*time.Second, 2*time.Second).Should(Succeed())
		} else {
			Expect(err).NotTo(HaveOccurred(), "Failed to check for FIS service-linked role")
		}
	}

	By("Creating FIS experiment role")
	uid, err := uuid.NewUUID()
	Expect(err).NotTo(HaveOccurred())
	shortUID := uid.String()[:8]
	fisRoleName = fmt.Sprintf("Karp-FIS-Role-%s", shortUID)
	assumeRolePolicy := fmt.Sprintf(`{
			"Version": "2012-10-17",
			"Statement": [
			{
				"Effect": "Allow",
				"Principal": {
					"Service": "fis.amazonaws.com"
				},
				"Action": "sts:AssumeRole",
				"Condition": {
					"StringEquals": {
						"aws:SourceAccount": "%s"
					},
					"ArnLike": {
						"aws:SourceArn": "arn:aws:fis:%s:%s:experiment/*"
					}
				}
			}
		]
	}`, env.ExpectAccountID(), env.Region, env.ExpectAccountID())

	createRoleOutput, err := env.IAMAPI.CreateRole(env.Context, &awsiam.CreateRoleInput{
		RoleName:                 aws.String(fisRoleName),
		AssumeRolePolicyDocument: aws.String(assumeRolePolicy),
		Description:              aws.String("Role for Karpenter zonal failure testing with AWS FIS"),
		Tags: []iamtypes.Tag{
			{
				Key:   aws.String(coretest.DiscoveryLabel),
				Value: aws.String(env.ClusterName),
			},
		},
	})
	Expect(err).NotTo(HaveOccurred())
	fisRoleArn = *createRoleOutput.Role.Arn

	// Attach AWS managed policies for FIS
	_, err = env.IAMAPI.AttachRolePolicy(env.Context, &awsiam.AttachRolePolicyInput{
		RoleName:  aws.String(fisRoleName),
		PolicyArn: aws.String("arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access"),
	})
	Expect(err).NotTo(HaveOccurred())
	_, err = env.IAMAPI.AttachRolePolicy(env.Context, &awsiam.AttachRolePolicyInput{
		RoleName:  aws.String(fisRoleName),
		PolicyArn: aws.String("arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess"),
	})
	Expect(err).NotTo(HaveOccurred())

	// Create custom policy for API error injection
	By("Creating custom policy for API error injection")
	policyName := fmt.Sprintf("Karp-FIS-APIError-Policy-%s", shortUID)
	policyDocument := fmt.Sprintf(`{
		"Version": "2012-10-17",
		"Statement": [
			{
				"Effect": "Allow",
				"Action": [
					"ec2:InjectApiError"
				],
				"Resource": "*",
				"Condition": {
					"StringEquals": {
						"ec2:FisActionId": "aws:ec2:api-insufficient-instance-capacity-error"
					},
					"ArnLike": {
						"ec2:FisTargetArns": [
							"arn:aws:iam::%s:role/KarpenterNodeRole-%s"
						]
					}
				}
			}
		]
	}`, env.ExpectAccountID(), env.ClusterName)

	createPolicyOutput, err := env.IAMAPI.CreatePolicy(env.Context, &awsiam.CreatePolicyInput{
		PolicyName:     aws.String(policyName),
		PolicyDocument: aws.String(policyDocument),
		Description:    aws.String("Policy for Karpenter zonal failure API error injection with AWS FIS"),
		Tags: []iamtypes.Tag{
			{
				Key:   aws.String(coretest.DiscoveryLabel),
				Value: aws.String(env.ClusterName),
			},
		},
	})
	Expect(err).NotTo(HaveOccurred())
	customPolicyArn = *createPolicyOutput.Policy.Arn
	_, err = env.IAMAPI.AttachRolePolicy(env.Context, &awsiam.AttachRolePolicyInput{
		RoleName:  aws.String(fisRoleName),
		PolicyArn: createPolicyOutput.Policy.Arn,
	})
	Expect(err).NotTo(HaveOccurred())

	// Wait for role to propagate
	time.Sleep(10 * time.Second)
}

func cleanupRoles(env *awsenv.Environment) {
	listPoliciesOutput, err := env.IAMAPI.ListAttachedRolePolicies(env.Context, &awsiam.ListAttachedRolePoliciesInput{
		RoleName: aws.String(fisRoleName),
	})
	Expect(err).NotTo(HaveOccurred())
	for _, policy := range listPoliciesOutput.AttachedPolicies {
		_, err = env.IAMAPI.DetachRolePolicy(env.Context, &awsiam.DetachRolePolicyInput{
			RoleName:  aws.String(fisRoleName),
			PolicyArn: policy.PolicyArn,
		})
		Expect(err).NotTo(HaveOccurred())
	}

	_, err = env.IAMAPI.DeletePolicy(env.Context, &awsiam.DeletePolicyInput{
		PolicyArn: aws.String(customPolicyArn),
	})
	Expect(err).NotTo(HaveOccurred())

	_, _ = env.IAMAPI.DeleteRole(env.Context, &awsiam.DeleteRoleInput{
		RoleName: aws.String(fisRoleName),
	})
}

func getSubnetsInAZ(ctx context.Context, env *awsenv.Environment, targetAZ string) []string {
	describeSubnetsOutput, err := env.EC2API.DescribeSubnets(ctx, &ec2.DescribeSubnetsInput{
		Filters: []ec2types.Filter{
			{
				Name:   aws.String("availability-zone"),
				Values: []string{targetAZ},
			},
			{
				Name:   aws.String("tag:karpenter.sh/discovery"),
				Values: []string{env.ClusterName},
			},
		},
	})
	Expect(err).NotTo(HaveOccurred())

	arns := lo.Map(describeSubnetsOutput.Subnets, func(subnet ec2types.Subnet, _ int) string {
		return *subnet.SubnetArn
	})
	Expect(len(arns)).To(BeNumerically(">", 0),
		fmt.Sprintf("No subnets found in AZ %s", targetAZ))

	return arns
}
