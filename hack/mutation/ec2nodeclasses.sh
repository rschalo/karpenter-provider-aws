#!/usr/bin/env bash

echo "  versions:
{{- if .Values.webhook.enabled }}
    - additionalPrinterColumns:
        - jsonPath: .status.conditions[?(@.type==\"Ready\")].status
          name: Ready
          type: string
        - jsonPath: .metadata.creationTimestamp
          name: Age
          type: date
        - jsonPath: .spec.role
          name: Role
          priority: 1
          type: string
      name: v1
      schema:
        openAPIV3Schema:
          description: EC2NodeClass is the Schema for the EC2NodeClass API
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
            spec:
              description: |-
                EC2NodeClassSpec is the top level specification for the AWS Karpenter Provider.
                This will contain configuration necessary to launch instances in AWS.
              properties:
                amiFamily:
                  description: |-
                    AMIFamily dictates the UserData format and default BlockDeviceMappings used when generating launch templates.
                    This field is optional when using an alias amiSelectorTerm, and the value will be inferred from the alias'
                    family. When an alias is specified, this field may only be set to its corresponding family or 'Custom'. If no
                    alias is specified, this field is required.
                    NOTE: We ignore the AMIFamily for hashing here because we hash the AMIFamily dynamically by using the alias using
                    the AMIFamily() helper function
                  enum:
                    - AL2
                    - AL2023
                    - Bottlerocket
                    - Custom
                    - Windows2019
                    - Windows2022
                  type: string
                amiSelectorTerms:
                  description: AMISelectorTerms is a list of or ami selector terms. The terms are ORed.
                  items:
                    description: |-
                      AMISelectorTerm defines selection logic for an ami used by Karpenter to launch nodes.
                      If multiple fields are used for selection, the requirements are ANDed.
                    properties:
                      alias:
                        description: |-
                          Alias specifies which EKS optimized AMI to select.
                          Each alias consists of a family and an AMI version, specified as \"family@version\".
                          Valid families include: al2, al2023, bottlerocket, windows2019, and windows2022.
                          The version can either be pinned to a specific AMI release, with that AMIs version format (ex: \"al2023@v20240625\" or \"bottlerocket@v1.10.0\").
                          The version can also be set to \"latest\" for any family. Setting the version to latest will result in drift when a new AMI is released. This is **not** recommended for production environments.
                          Note: The Windows families do **not** support version pinning, and only latest may be used.
                        maxLength: 30
                        type: string
                        x-kubernetes-validations:
                          - message: '''alias'' is improperly formatted, must match the format ''family@version'''
                            rule: self.matches('^[a-zA-Z0-9]*@.*$')
                          - message: 'family is not supported, must be one of the following: ''al2'', ''al2023'', ''bottlerocket'', ''windows2019'', ''windows2022'''
                            rule: self.find('^[^@]+') in ['al2','al2023','bottlerocket','windows2019','windows2022']
                      id:
                        description: ID is the ami id in EC2
                        pattern: ami-[0-9a-z]+
                        type: string
                      name:
                        description: |-
                          Name is the ami name in EC2.
                          This value is the name field, which is different from the name tag.
                        type: string
                      owner:
                        description: |-
                          Owner is the owner for the ami.
                          You can specify a combination of AWS account IDs, \"self\", \"amazon\", and \"aws-marketplace\"
                        type: string
                      tags:
                        additionalProperties:
                          type: string
                        description: |-
                          Tags is a map of key/value tags used to select subnets
                          Specifying '*' for a value selects all values for a given tag key.
                        maxProperties: 20
                        type: object
                        x-kubernetes-validations:
                          - message: empty tag keys or values aren't supported
                            rule: self.all(k, k != '' && self[k] != '')
                    type: object
                  maxItems: 30
                  minItems: 1
                  type: array
                  x-kubernetes-validations:
                    - message: expected at least one, got none, ['tags', 'id', 'name', 'alias']
                      rule: self.all(x, has(x.tags) || has(x.id) || has(x.name) || has(x.alias))
                    - message: '''id'' is mutually exclusive, cannot be set with a combination of other fields in amiSelectorTerms'
                      rule: '!self.exists(x, has(x.id) && (has(x.alias) || has(x.tags) || has(x.name) || has(x.owner)))'
                    - message: '''alias'' is mutually exclusive, cannot be set with a combination of other fields in amiSelectorTerms'
                      rule: '!self.exists(x, has(x.alias) && (has(x.id) || has(x.tags) || has(x.name) || has(x.owner)))'
                    - message: '''alias'' is mutually exclusive, cannot be set with a combination of other amiSelectorTerms'
                      rule: '!(self.exists(x, has(x.alias)) && self.size() != 1)'
                associatePublicIPAddress:
                  description: AssociatePublicIPAddress controls if public IP addresses are assigned to instances that are launched with the nodeclass.
                  type: boolean
                blockDeviceMappings:
                  description: BlockDeviceMappings to be applied to provisioned nodes.
                  items:
                    properties:
                      deviceName:
                        description: The device name (for example, /dev/sdh or xvdh).
                        type: string
                      ebs:
                        description: EBS contains parameters used to automatically set up EBS volumes when an instance is launched.
                        properties:
                          deleteOnTermination:
                            description: DeleteOnTermination indicates whether the EBS volume is deleted on instance termination.
                            type: boolean
                          encrypted:
                            description: |-
                              Encrypted indicates whether the EBS volume is encrypted. Encrypted volumes can only
                              be attached to instances that support Amazon EBS encryption. If you are creating
                              a volume from a snapshot, you can't specify an encryption value.
                            type: boolean
                          iops:
                            description: |-
                              IOPS is the number of I/O operations per second (IOPS). For gp3, io1, and io2 volumes,
                              this represents the number of IOPS that are provisioned for the volume. For
                              gp2 volumes, this represents the baseline performance of the volume and the
                              rate at which the volume accumulates I/O credits for bursting.

                              The following are the supported values for each volume type:

                                 * gp3: 3,000-16,000 IOPS

                                 * io1: 100-64,000 IOPS

                                 * io2: 100-64,000 IOPS

                              For io1 and io2 volumes, we guarantee 64,000 IOPS only for Instances built
                              on the Nitro System (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html#ec2-nitro-instances).
                              Other instance families guarantee performance up to 32,000 IOPS.

                              This parameter is supported for io1, io2, and gp3 volumes only. This parameter
                              is not supported for gp2, st1, sc1, or standard volumes.
                            format: int64
                            type: integer
                          kmsKeyID:
                            description: KMSKeyID (ARN) of the symmetric Key Management Service (KMS) CMK used for encryption.
                            type: string
                          snapshotID:
                            description: SnapshotID is the ID of an EBS snapshot
                            type: string
                          throughput:
                            description: |-
                              Throughput to provision for a gp3 volume, with a maximum of 1,000 MiB/s.
                              Valid Range: Minimum value of 125. Maximum value of 1000.
                            format: int64
                            type: integer
                          volumeSize:
                            description: |-
                              VolumeSize in \`Gi\`, \`G\`, \`Ti\`, or \`T\`. You must specify either a snapshot ID or
                              a volume size. The following are the supported volumes sizes for each volume
                              type:

                                 * gp2 and gp3: 1-16,384

                                 * io1 and io2: 4-16,384

                                 * st1 and sc1: 125-16,384

                                 * standard: 1-1,024
                            pattern: ^((?:[1-9][0-9]{0,3}|[1-4][0-9]{4}|[5][0-8][0-9]{3}|59000)Gi|(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|[6][0-3][0-9]{3}|64000)G|([1-9]||[1-5][0-7]|58)Ti|([1-9]||[1-5][0-9]|6[0-3]|64)T)$
                            type: string
                          volumeType:
                            description: |-
                              VolumeType of the block device.
                              For more information, see Amazon EBS volume types (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumeTypes.html)
                              in the Amazon Elastic Compute Cloud User Guide.
                            enum:
                              - standard
                              - io1
                              - io2
                              - gp2
                              - sc1
                              - st1
                              - gp3
                            type: string
                        type: object
                        x-kubernetes-validations:
                          - message: snapshotID or volumeSize must be defined
                            rule: has(self.snapshotID) || has(self.volumeSize)
                      rootVolume:
                        description: |-
                          RootVolume is a flag indicating if this device is mounted as kubelet root dir. You can
                          configure at most one root volume in BlockDeviceMappings.
                        type: boolean
                    type: object
                  maxItems: 50
                  type: array
                  x-kubernetes-validations:
                    - message: must have only one blockDeviceMappings with rootVolume
                      rule: self.filter(x, has(x.rootVolume)?x.rootVolume==true:false).size() <= 1
                context:
                  description: |-
                    Context is a Reserved field in EC2 APIs
                    https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_CreateFleet.html
                  type: string
                detailedMonitoring:
                  description: DetailedMonitoring controls if detailed monitoring is enabled for instances that are launched
                  type: boolean
                instanceProfile:
                  description: |-
                    InstanceProfile is the AWS entity that instances use.
                    This field is mutually exclusive from role.
                    The instance profile should already have a role assigned to it that Karpenter
                     has PassRole permission on for instance launch using this instanceProfile to succeed.
                  type: string
                  x-kubernetes-validations:
                    - message: instanceProfile cannot be empty
                      rule: self != ''
                instanceStorePolicy:
                  description: InstanceStorePolicy specifies how to handle instance-store disks.
                  enum:
                    - RAID0
                  type: string
                kubelet:
                  description: |-
                    Kubelet defines args to be used when configuring kubelet on provisioned nodes.
                    They are a subset of the upstream types, recognizing not all options may be supported.
                    Wherever possible, the types and names should reflect the upstream kubelet types.
                  properties:
                    clusterDNS:
                      description: |-
                        clusterDNS is a list of IP addresses for the cluster DNS server.
                        Note that not all providers may use all addresses.
                      items:
                        type: string
                      type: array
                    cpuCFSQuota:
                      description: CPUCFSQuota enables CPU CFS quota enforcement for containers that specify CPU limits.
                      type: boolean
                    evictionHard:
                      additionalProperties:
                        type: string
                        pattern: ^((\d{1,2}(\.\d{1,2})?|100(\.0{1,2})?)%||(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?)$
                      description: EvictionHard is the map of signal names to quantities that define hard eviction thresholds
                      type: object
                      x-kubernetes-validations:
                        - message: valid keys for evictionHard are ['memory.available','nodefs.available','nodefs.inodesFree','imagefs.available','imagefs.inodesFree','pid.available']
                          rule: self.all(x, x in ['memory.available','nodefs.available','nodefs.inodesFree','imagefs.available','imagefs.inodesFree','pid.available'])
                    evictionMaxPodGracePeriod:
                      description: |-
                        EvictionMaxPodGracePeriod is the maximum allowed grace period (in seconds) to use when terminating pods in
                        response to soft eviction thresholds being met.
                      format: int32
                      type: integer
                    evictionSoft:
                      additionalProperties:
                        type: string
                        pattern: ^((\d{1,2}(\.\d{1,2})?|100(\.0{1,2})?)%||(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?)$
                      description: EvictionSoft is the map of signal names to quantities that define soft eviction thresholds
                      type: object
                      x-kubernetes-validations:
                        - message: valid keys for evictionSoft are ['memory.available','nodefs.available','nodefs.inodesFree','imagefs.available','imagefs.inodesFree','pid.available']
                          rule: self.all(x, x in ['memory.available','nodefs.available','nodefs.inodesFree','imagefs.available','imagefs.inodesFree','pid.available'])
                    evictionSoftGracePeriod:
                      additionalProperties:
                        type: string
                      description: EvictionSoftGracePeriod is the map of signal names to quantities that define grace periods for each eviction signal
                      type: object
                      x-kubernetes-validations:
                        - message: valid keys for evictionSoftGracePeriod are ['memory.available','nodefs.available','nodefs.inodesFree','imagefs.available','imagefs.inodesFree','pid.available']
                          rule: self.all(x, x in ['memory.available','nodefs.available','nodefs.inodesFree','imagefs.available','imagefs.inodesFree','pid.available'])
                    imageGCHighThresholdPercent:
                      description: |-
                        ImageGCHighThresholdPercent is the percent of disk usage after which image
                        garbage collection is always run. The percent is calculated by dividing this
                        field value by 100, so this field must be between 0 and 100, inclusive.
                        When specified, the value must be greater than ImageGCLowThresholdPercent.
                      format: int32
                      maximum: 100
                      minimum: 0
                      type: integer
                    imageGCLowThresholdPercent:
                      description: |-
                        ImageGCLowThresholdPercent is the percent of disk usage before which image
                        garbage collection is never run. Lowest disk usage to garbage collect to.
                        The percent is calculated by dividing this field value by 100,
                        so the field value must be between 0 and 100, inclusive.
                        When specified, the value must be less than imageGCHighThresholdPercent
                      format: int32
                      maximum: 100
                      minimum: 0
                      type: integer
                    kubeReserved:
                      additionalProperties:
                        type: string
                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                      description: KubeReserved contains resources reserved for Kubernetes system components.
                      type: object
                      x-kubernetes-validations:
                        - message: valid keys for kubeReserved are ['cpu','memory','ephemeral-storage','pid']
                          rule: self.all(x, x=='cpu' || x=='memory' || x=='ephemeral-storage' || x=='pid')
                        - message: kubeReserved value cannot be a negative resource quantity
                          rule: self.all(x, !self[x].startsWith('-'))
                    maxPods:
                      description: |-
                        MaxPods is an override for the maximum number of pods that can run on
                        a worker node instance.
                      format: int32
                      minimum: 0
                      type: integer
                    podsPerCore:
                      description: |-
                        PodsPerCore is an override for the number of pods that can run on a worker node
                        instance based on the number of cpu cores. This value cannot exceed MaxPods, so, if
                        MaxPods is a lower value, that value will be used.
                      format: int32
                      minimum: 0
                      type: integer
                    systemReserved:
                      additionalProperties:
                        type: string
                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                      description: SystemReserved contains resources reserved for OS system daemons and kernel memory.
                      type: object
                      x-kubernetes-validations:
                        - message: valid keys for systemReserved are ['cpu','memory','ephemeral-storage','pid']
                          rule: self.all(x, x=='cpu' || x=='memory' || x=='ephemeral-storage' || x=='pid')
                        - message: systemReserved value cannot be a negative resource quantity
                          rule: self.all(x, !self[x].startsWith('-'))
                  type: object
                  x-kubernetes-validations:
                    - message: imageGCHighThresholdPercent must be greater than imageGCLowThresholdPercent
                      rule: 'has(self.imageGCHighThresholdPercent) && has(self.imageGCLowThresholdPercent) ?  self.imageGCHighThresholdPercent > self.imageGCLowThresholdPercent  : true'
                    - message: evictionSoft OwnerKey does not have a matching evictionSoftGracePeriod
                      rule: has(self.evictionSoft) ? self.evictionSoft.all(e, (e in self.evictionSoftGracePeriod)):true
                    - message: evictionSoftGracePeriod OwnerKey does not have a matching evictionSoft
                      rule: has(self.evictionSoftGracePeriod) ? self.evictionSoftGracePeriod.all(e, (e in self.evictionSoft)):true
                metadataOptions:
                  default:
                    httpEndpoint: enabled
                    httpProtocolIPv6: disabled
                    httpPutResponseHopLimit: 1
                    httpTokens: required
                  description: |-
                    MetadataOptions for the generated launch template of provisioned nodes.

                    This specifies the exposure of the Instance Metadata Service to
                    provisioned EC2 nodes. For more information,
                    see Instance Metadata and User Data
                    (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html)
                    in the Amazon Elastic Compute Cloud User Guide.

                    Refer to recommended, security best practices
                    (https://aws.github.io/aws-eks-best-practices/security/docs/iam/#restrict-access-to-the-instance-profile-assigned-to-the-worker-node)
                    for limiting exposure of Instance Metadata and User Data to pods.
                    If omitted, defaults to httpEndpoint enabled, with httpProtocolIPv6
                    disabled, with httpPutResponseLimit of 1, and with httpTokens
                    required.
                  properties:
                    httpEndpoint:
                      default: enabled
                      description: |-
                        HTTPEndpoint enables or disables the HTTP metadata endpoint on provisioned
                        nodes. If metadata options is non-nil, but this parameter is not specified,
                        the default state is \"enabled\".

                        If you specify a value of \"disabled\", instance metadata will not be accessible
                        on the node.
                      enum:
                        - enabled
                        - disabled
                      type: string
                    httpProtocolIPv6:
                      default: disabled
                      description: |-
                        HTTPProtocolIPv6 enables or disables the IPv6 endpoint for the instance metadata
                        service on provisioned nodes. If metadata options is non-nil, but this parameter
                        is not specified, the default state is \"disabled\".
                      enum:
                        - enabled
                        - disabled
                      type: string
                    httpPutResponseHopLimit:
                      default: 1
                      description: |-
                        HTTPPutResponseHopLimit is the desired HTTP PUT response hop limit for
                        instance metadata requests. The larger the number, the further instance
                        metadata requests can travel. Possible values are integers from 1 to 64.
                        If metadata options is non-nil, but this parameter is not specified, the
                        default value is 1.
                      format: int64
                      maximum: 64
                      minimum: 1
                      type: integer
                    httpTokens:
                      default: required
                      description: |-
                        HTTPTokens determines the state of token usage for instance metadata
                        requests. If metadata options is non-nil, but this parameter is not
                        specified, the default state is \"required\".

                        If the state is optional, one can choose to retrieve instance metadata with
                        or without a signed token header on the request. If one retrieves the IAM
                        role credentials without a token, the version 1.0 role credentials are
                        returned. If one retrieves the IAM role credentials using a valid signed
                        token, the version 2.0 role credentials are returned.

                        If the state is \"required\", one must send a signed token header with any
                        instance metadata retrieval requests. In this state, retrieving the IAM
                        role credentials always returns the version 2.0 credentials; the version
                        1.0 credentials are not available.
                      enum:
                        - required
                        - optional
                      type: string
                  type: object
                role:
                  description: |-
                    Role is the AWS identity that nodes use. This field is immutable.
                    This field is mutually exclusive from instanceProfile.
                    Marking this field as immutable avoids concerns around terminating managed instance profiles from running instances.
                    This field may be made mutable in the future, assuming the correct garbage collection and drift handling is implemented
                    for the old instance profiles on an update.
                  type: string
                  x-kubernetes-validations:
                    - message: role cannot be empty
                      rule: self != ''
                    - message: immutable field changed
                      rule: self == oldSelf
                securityGroupSelectorTerms:
                  description: SecurityGroupSelectorTerms is a list of or security group selector terms. The terms are ORed.
                  items:
                    description: |-
                      SecurityGroupSelectorTerm defines selection logic for a security group used by Karpenter to launch nodes.
                      If multiple fields are used for selection, the requirements are ANDed.
                    properties:
                      id:
                        description: ID is the security group id in EC2
                        pattern: sg-[0-9a-z]+
                        type: string
                      name:
                        description: |-
                          Name is the security group name in EC2.
                          This value is the name field, which is different from the name tag.
                        type: string
                      tags:
                        additionalProperties:
                          type: string
                        description: |-
                          Tags is a map of key/value tags used to select subnets
                          Specifying '*' for a value selects all values for a given tag key.
                        maxProperties: 20
                        type: object
                        x-kubernetes-validations:
                          - message: empty tag keys or values aren't supported
                            rule: self.all(k, k != '' && self[k] != '')
                    type: object
                  maxItems: 30
                  type: array
                  x-kubernetes-validations:
                    - message: securityGroupSelectorTerms cannot be empty
                      rule: self.size() != 0
                    - message: expected at least one, got none, ['tags', 'id', 'name']
                      rule: self.all(x, has(x.tags) || has(x.id) || has(x.name))
                    - message: '''id'' is mutually exclusive, cannot be set with a combination of other fields in securityGroupSelectorTerms'
                      rule: '!self.all(x, has(x.id) && (has(x.tags) || has(x.name)))'
                    - message: '''name'' is mutually exclusive, cannot be set with a combination of other fields in securityGroupSelectorTerms'
                      rule: '!self.all(x, has(x.name) && (has(x.tags) || has(x.id)))'
                subnetSelectorTerms:
                  description: SubnetSelectorTerms is a list of or subnet selector terms. The terms are ORed.
                  items:
                    description: |-
                      SubnetSelectorTerm defines selection logic for a subnet used by Karpenter to launch nodes.
                      If multiple fields are used for selection, the requirements are ANDed.
                    properties:
                      id:
                        description: ID is the subnet id in EC2
                        pattern: subnet-[0-9a-z]+
                        type: string
                      tags:
                        additionalProperties:
                          type: string
                        description: |-
                          Tags is a map of key/value tags used to select subnets
                          Specifying '*' for a value selects all values for a given tag key.
                        maxProperties: 20
                        type: object
                        x-kubernetes-validations:
                          - message: empty tag keys or values aren't supported
                            rule: self.all(k, k != '' && self[k] != '')
                    type: object
                  maxItems: 30
                  type: array
                  x-kubernetes-validations:
                    - message: subnetSelectorTerms cannot be empty
                      rule: self.size() != 0
                    - message: expected at least one, got none, ['tags', 'id']
                      rule: self.all(x, has(x.tags) || has(x.id))
                    - message: '''id'' is mutually exclusive, cannot be set with a combination of other fields in subnetSelectorTerms'
                      rule: '!self.all(x, has(x.id) && has(x.tags))'
                tags:
                  additionalProperties:
                    type: string
                  description: Tags to be applied on ec2 resources like instances and launch templates.
                  type: object
                  x-kubernetes-validations:
                    - message: empty tag keys aren't supported
                      rule: self.all(k, k != '')
                    - message: tag contains a restricted tag matching eks:eks-cluster-name
                      rule: self.all(k, k !='eks:eks-cluster-name')
                    - message: tag contains a restricted tag matching kubernetes.io/cluster/
                      rule: self.all(k, !k.startsWith('kubernetes.io/cluster') )
                    - message: tag contains a restricted tag matching karpenter.sh/nodepool
                      rule: self.all(k, k != 'karpenter.sh/nodepool')
                    - message: tag contains a restricted tag matching karpenter.sh/nodeclaim
                      rule: self.all(k, k !='karpenter.sh/nodeclaim')
                    - message: tag contains a restricted tag matching karpenter.k8s.aws/ec2nodeclass
                      rule: self.all(k, k !='karpenter.k8s.aws/ec2nodeclass')
                userData:
                  description: |-
                    UserData to be applied to the provisioned nodes.
                    It must be in the appropriate format based on the AMIFamily in use. Karpenter will merge certain fields into
                    this UserData to ensure nodes are being provisioned with the correct configuration.
                  type: string
              required:
                - amiSelectorTerms
                - securityGroupSelectorTerms
                - subnetSelectorTerms
              type: object
              x-kubernetes-validations:
                - message: must specify exactly one of ['role', 'instanceProfile']
                  rule: (has(self.role) && !has(self.instanceProfile)) || (!has(self.role) && has(self.instanceProfile))
                - message: changing from 'instanceProfile' to 'role' is not supported. You must delete and recreate this node class if you want to change this.
                  rule: (has(oldSelf.role) && has(self.role)) || (has(oldSelf.instanceProfile) && has(self.instanceProfile))
                - message: if set, amiFamily must be 'AL2' or 'Custom' when using an AL2 alias
                  rule: '!has(self.amiFamily) || (self.amiSelectorTerms.exists(x, has(x.alias) && x.alias.find(''^[^@]+'') == ''al2'') ? (self.amiFamily == ''Custom'' || self.amiFamily == ''AL2'') : true)'
                - message: if set, amiFamily must be 'AL2023' or 'Custom' when using an AL2023 alias
                  rule: '!has(self.amiFamily) || (self.amiSelectorTerms.exists(x, has(x.alias) && x.alias.find(''^[^@]+'') == ''al2023'') ? (self.amiFamily == ''Custom'' || self.amiFamily == ''AL2023'') : true)'
                - message: if set, amiFamily must be 'Bottlerocket' or 'Custom' when using a Bottlerocket alias
                  rule: '!has(self.amiFamily) || (self.amiSelectorTerms.exists(x, has(x.alias) && x.alias.find(''^[^@]+'') == ''bottlerocket'') ? (self.amiFamily == ''Custom'' || self.amiFamily == ''Bottlerocket'') : true)'
                - message: if set, amiFamily must be 'Windows2019' or 'Custom' when using a Windows2019 alias
                  rule: '!has(self.amiFamily) || (self.amiSelectorTerms.exists(x, has(x.alias) && x.alias.find(''^[^@]+'') == ''windows2019'') ? (self.amiFamily == ''Custom'' || self.amiFamily == ''Windows2019'') : true)'
                - message: if set, amiFamily must be 'Windows2022' or 'Custom' when using a Windows2022 alias
                  rule: '!has(self.amiFamily) || (self.amiSelectorTerms.exists(x, has(x.alias) && x.alias.find(''^[^@]+'') == ''windows2022'') ? (self.amiFamily == ''Custom'' || self.amiFamily == ''Windows2022'') : true)'
                - message: must specify amiFamily if amiSelectorTerms does not contain an alias
                  rule: 'self.amiSelectorTerms.exists(x, has(x.alias)) ? true : has(self.amiFamily)'
            status:
              description: EC2NodeClassStatus contains the resolved state of the EC2NodeClass
              properties:
                amis:
                  description: |-
                    AMI contains the current AMI values that are available to the
                    cluster under the AMI selectors.
                  items:
                    description: AMI contains resolved AMI selector values utilized for node launch
                    properties:
                      id:
                        description: ID of the AMI
                        type: string
                      name:
                        description: Name of the AMI
                        type: string
                      requirements:
                        description: Requirements of the AMI to be utilized on an instance type
                        items:
                          description: |-
                            A node selector requirement is a selector that contains values, a key, and an operator
                            that relates the key and values.
                          properties:
                            key:
                              description: The label key that the selector applies to.
                              type: string
                            operator:
                              description: |-
                                Represents a key's relationship to a set of values.
                                Valid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.
                              type: string
                            values:
                              description: |-
                                An array of string values. If the operator is In or NotIn,
                                the values array must be non-empty. If the operator is Exists or DoesNotExist,
                                the values array must be empty. If the operator is Gt or Lt, the values
                                array must have a single element, which will be interpreted as an integer.
                                This array is replaced during a strategic merge patch.
                              items:
                                type: string
                              type: array
                              x-kubernetes-list-type: atomic
                          required:
                            - key
                            - operator
                          type: object
                        type: array
                    required:
                      - id
                      - requirements
                    type: object
                  type: array
                conditions:
                  description: Conditions contains signals for health and readiness
                  items:
                    description: Condition aliases the upstream type and adds additional helper methods
                    properties:
                      lastTransitionTime:
                        description: |-
                          lastTransitionTime is the last time the condition transitioned from one status to another.
                          This should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.
                        format: date-time
                        type: string
                      message:
                        description: |-
                          message is a human readable message indicating details about the transition.
                          This may be an empty string.
                        maxLength: 32768
                        type: string
                      observedGeneration:
                        description: |-
                          observedGeneration represents the .metadata.generation that the condition was set based upon.
                          For instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date
                          with respect to the current state of the instance.
                        format: int64
                        minimum: 0
                        type: integer
                      reason:
                        description: |-
                          reason contains a programmatic identifier indicating the reason for the condition's last transition.
                          Producers of specific condition types may define expected values and meanings for this field,
                          and whether the values are considered a guaranteed API.
                          The value should be a CamelCase string.
                          This field may not be empty.
                        maxLength: 1024
                        minLength: 1
                        pattern: ^[A-Za-z]([A-Za-z0-9_,:]*[A-Za-z0-9_])?$
                        type: string
                      status:
                        description: status of the condition, one of True, False, Unknown.
                        enum:
                          - \"True\"
                          - \"False\"
                          - Unknown
                        type: string
                      type:
                        description: type of condition in CamelCase or in foo.example.com/CamelCase.
                        maxLength: 316
                        pattern: ^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?(([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])$
                        type: string
                    required:
                      - lastTransitionTime
                      - message
                      - reason
                      - status
                      - type
                    type: object
                  type: array
                instanceProfile:
                  description: InstanceProfile contains the resolved instance profile for the role
                  type: string
                securityGroups:
                  description: |-
                    SecurityGroups contains the current Security Groups values that are available to the
                    cluster under the SecurityGroups selectors.
                  items:
                    description: SecurityGroup contains resolved SecurityGroup selector values utilized for node launch
                    properties:
                      id:
                        description: ID of the security group
                        type: string
                      name:
                        description: Name of the security group
                        type: string
                    required:
                      - id
                    type: object
                  type: array
                subnets:
                  description: |-
                    Subnets contains the current Subnet values that are available to the
                    cluster under the subnet selectors.
                  items:
                    description: Subnet contains resolved Subnet selector values utilized for node launch
                    properties:
                      id:
                        description: ID of the subnet
                        type: string
                      zone:
                        description: The associated availability zone
                        type: string
                      zoneID:
                        description: The associated availability zone ID
                        type: string
                    required:
                      - id
                      - zone
                    type: object
                  type: array
              type: object
          type: object
      served: true
      storage: false
      subresources:
        status: {}
{{- end }}
    - name: v1beta1
      schema:
        openAPIV3Schema:
          description: EC2NodeClass is the Schema for the EC2NodeClass API
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
            spec:
              description: |-
                EC2NodeClassSpec is the top level specification for the AWS Karpenter Provider.
                This will contain configuration necessary to launch instances in AWS.
              properties:
                amiFamily:
                  description: AMIFamily is the AMI family that instances use.
                  enum:
                    - AL2
                    - AL2023
                    - Bottlerocket
                    - Ubuntu
                    - Custom
                    - Windows2019
                    - Windows2022
                  type: string
                amiSelectorTerms:
                  description: AMISelectorTerms is a list of or ami selector terms. The terms are ORed.
                  items:
                    description: |-
                      AMISelectorTerm defines selection logic for an ami used by Karpenter to launch nodes.
                      If multiple fields are used for selection, the requirements are ANDed.
                    properties:
                      id:
                        description: ID is the ami id in EC2
                        pattern: ami-[0-9a-z]+
                        type: string
                      name:
                        description: |-
                          Name is the ami name in EC2.
                          This value is the name field, which is different from the name tag.
                        type: string
                      owner:
                        description: |-
                          Owner is the owner for the ami.
                          You can specify a combination of AWS account IDs, \"self\", \"amazon\", and \"aws-marketplace\"
                        type: string
                      tags:
                        additionalProperties:
                          type: string
                        description: |-
                          Tags is a map of key/value tags used to select subnets
                          Specifying '*' for a value selects all values for a given tag key.
                        maxProperties: 20
                        type: object
                        x-kubernetes-validations:
                          - message: empty tag keys or values aren't supported
                            rule: self.all(k, k != '' && self[k] != '')
                    type: object
                  maxItems: 30
                  type: array
                  x-kubernetes-validations:
                    - message: expected at least one, got none, ['tags', 'id', 'name']
                      rule: self.all(x, has(x.tags) || has(x.id) || has(x.name))
                    - message: '''id'' is mutually exclusive, cannot be set with a combination of other fields in amiSelectorTerms'
                      rule: '!self.all(x, has(x.id) && (has(x.tags) || has(x.name) || has(x.owner)))'
                associatePublicIPAddress:
                  description: AssociatePublicIPAddress controls if public IP addresses are assigned to instances that are launched with the nodeclass.
                  type: boolean
                blockDeviceMappings:
                  description: BlockDeviceMappings to be applied to provisioned nodes.
                  items:
                    properties:
                      deviceName:
                        description: The device name (for example, /dev/sdh or xvdh).
                        type: string
                      ebs:
                        description: EBS contains parameters used to automatically set up EBS volumes when an instance is launched.
                        properties:
                          deleteOnTermination:
                            description: DeleteOnTermination indicates whether the EBS volume is deleted on instance termination.
                            type: boolean
                          encrypted:
                            description: |-
                              Encrypted indicates whether the EBS volume is encrypted. Encrypted volumes can only
                              be attached to instances that support Amazon EBS encryption. If you are creating
                              a volume from a snapshot, you can't specify an encryption value.
                            type: boolean
                          iops:
                            description: |-
                              IOPS is the number of I/O operations per second (IOPS). For gp3, io1, and io2 volumes,
                              this represents the number of IOPS that are provisioned for the volume. For
                              gp2 volumes, this represents the baseline performance of the volume and the
                              rate at which the volume accumulates I/O credits for bursting.

                              The following are the supported values for each volume type:

                                 * gp3: 3,000-16,000 IOPS

                                 * io1: 100-64,000 IOPS

                                 * io2: 100-64,000 IOPS

                              For io1 and io2 volumes, we guarantee 64,000 IOPS only for Instances built
                              on the Nitro System (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html#ec2-nitro-instances).
                              Other instance families guarantee performance up to 32,000 IOPS.

                              This parameter is supported for io1, io2, and gp3 volumes only. This parameter
                              is not supported for gp2, st1, sc1, or standard volumes.
                            format: int64
                            type: integer
                          kmsKeyID:
                            description: KMSKeyID (ARN) of the symmetric Key Management Service (KMS) CMK used for encryption.
                            type: string
                          snapshotID:
                            description: SnapshotID is the ID of an EBS snapshot
                            type: string
                          throughput:
                            description: |-
                              Throughput to provision for a gp3 volume, with a maximum of 1,000 MiB/s.
                              Valid Range: Minimum value of 125. Maximum value of 1000.
                            format: int64
                            type: integer
                          volumeSize:
                            description: |-
                              VolumeSize in \`Gi\`, \`G\`, \`Ti\`, or \`T\`. You must specify either a snapshot ID or
                              a volume size. The following are the supported volumes sizes for each volume
                              type:

                                 * gp2 and gp3: 1-16,384

                                 * io1 and io2: 4-16,384

                                 * st1 and sc1: 125-16,384

                                 * standard: 1-1,024
                            pattern: ^((?:[1-9][0-9]{0,3}|[1-4][0-9]{4}|[5][0-8][0-9]{3}|59000)Gi|(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|[6][0-3][0-9]{3}|64000)G|([1-9]||[1-5][0-7]|58)Ti|([1-9]||[1-5][0-9]|6[0-3]|64)T)$
                            type: string
                          volumeType:
                            description: |-
                              VolumeType of the block device.
                              For more information, see Amazon EBS volume types (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumeTypes.html)
                              in the Amazon Elastic Compute Cloud User Guide.
                            enum:
                              - standard
                              - io1
                              - io2
                              - gp2
                              - sc1
                              - st1
                              - gp3
                            type: string
                        type: object
                        x-kubernetes-validations:
                          - message: snapshotID or volumeSize must be defined
                            rule: has(self.snapshotID) || has(self.volumeSize)
                      rootVolume:
                        description: |-
                          RootVolume is a flag indicating if this device is mounted as kubelet root dir. You can
                          configure at most one root volume in BlockDeviceMappings.
                        type: boolean
                    type: object
                  maxItems: 50
                  type: array
                  x-kubernetes-validations:
                    - message: must have only one blockDeviceMappings with rootVolume
                      rule: self.filter(x, has(x.rootVolume)?x.rootVolume==true:false).size() <= 1
                context:
                  description: |-
                    Context is a Reserved field in EC2 APIs
                    https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_CreateFleet.html
                  type: string
                detailedMonitoring:
                  description: DetailedMonitoring controls if detailed monitoring is enabled for instances that are launched
                  type: boolean
                instanceProfile:
                  description: |-
                    InstanceProfile is the AWS entity that instances use.
                    This field is mutually exclusive from role.
                    The instance profile should already have a role assigned to it that Karpenter
                     has PassRole permission on for instance launch using this instanceProfile to succeed.
                  type: string
                  x-kubernetes-validations:
                    - message: instanceProfile cannot be empty
                      rule: self != ''
                instanceStorePolicy:
                  description: InstanceStorePolicy specifies how to handle instance-store disks.
                  enum:
                    - RAID0
                  type: string
                metadataOptions:
                  default:
                    httpEndpoint: enabled
                    httpProtocolIPv6: disabled
                    httpPutResponseHopLimit: 2
                    httpTokens: required
                  description: |-
                    MetadataOptions for the generated launch template of provisioned nodes.

                    This specifies the exposure of the Instance Metadata Service to
                    provisioned EC2 nodes. For more information,
                    see Instance Metadata and User Data
                    (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html)
                    in the Amazon Elastic Compute Cloud User Guide.

                    Refer to recommended, security best practices
                    (https://aws.github.io/aws-eks-best-practices/security/docs/iam/#restrict-access-to-the-instance-profile-assigned-to-the-worker-node)
                    for limiting exposure of Instance Metadata and User Data to pods.
                    If omitted, defaults to httpEndpoint enabled, with httpProtocolIPv6
                    disabled, with httpPutResponseLimit of 2, and with httpTokens
                    required.
                  properties:
                    httpEndpoint:
                      default: enabled
                      description: |-
                        HTTPEndpoint enables or disables the HTTP metadata endpoint on provisioned
                        nodes. If metadata options is non-nil, but this parameter is not specified,
                        the default state is \"enabled\".

                        If you specify a value of \"disabled\", instance metadata will not be accessible
                        on the node.
                      enum:
                        - enabled
                        - disabled
                      type: string
                    httpProtocolIPv6:
                      default: disabled
                      description: |-
                        HTTPProtocolIPv6 enables or disables the IPv6 endpoint for the instance metadata
                        service on provisioned nodes. If metadata options is non-nil, but this parameter
                        is not specified, the default state is \"disabled\".
                      enum:
                        - enabled
                        - disabled
                      type: string
                    httpPutResponseHopLimit:
                      default: 2
                      description: |-
                        HTTPPutResponseHopLimit is the desired HTTP PUT response hop limit for
                        instance metadata requests. The larger the number, the further instance
                        metadata requests can travel. Possible values are integers from 1 to 64.
                        If metadata options is non-nil, but this parameter is not specified, the
                        default value is 2.
                      format: int64
                      maximum: 64
                      minimum: 1
                      type: integer
                    httpTokens:
                      default: required
                      description: |-
                        HTTPTokens determines the state of token usage for instance metadata
                        requests. If metadata options is non-nil, but this parameter is not
                        specified, the default state is \"required\".

                        If the state is optional, one can choose to retrieve instance metadata with
                        or without a signed token header on the request. If one retrieves the IAM
                        role credentials without a token, the version 1.0 role credentials are
                        returned. If one retrieves the IAM role credentials using a valid signed
                        token, the version 2.0 role credentials are returned.

                        If the state is \"required\", one must send a signed token header with any
                        instance metadata retrieval requests. In this state, retrieving the IAM
                        role credentials always returns the version 2.0 credentials; the version
                        1.0 credentials are not available.
                      enum:
                        - required
                        - optional
                      type: string
                  type: object
                role:
                  description: |-
                    Role is the AWS identity that nodes use. This field is immutable.
                    This field is mutually exclusive from instanceProfile.
                    Marking this field as immutable avoids concerns around terminating managed instance profiles from running instances.
                    This field may be made mutable in the future, assuming the correct garbage collection and drift handling is implemented
                    for the old instance profiles on an update.
                  type: string
                  x-kubernetes-validations:
                    - message: role cannot be empty
                      rule: self != ''
                    - message: immutable field changed
                      rule: self == oldSelf
                securityGroupSelectorTerms:
                  description: SecurityGroupSelectorTerms is a list of or security group selector terms. The terms are ORed.
                  items:
                    description: |-
                      SecurityGroupSelectorTerm defines selection logic for a security group used by Karpenter to launch nodes.
                      If multiple fields are used for selection, the requirements are ANDed.
                    properties:
                      id:
                        description: ID is the security group id in EC2
                        pattern: sg-[0-9a-z]+
                        type: string
                      name:
                        description: |-
                          Name is the security group name in EC2.
                          This value is the name field, which is different from the name tag.
                        type: string
                      tags:
                        additionalProperties:
                          type: string
                        description: |-
                          Tags is a map of key/value tags used to select subnets
                          Specifying '*' for a value selects all values for a given tag key.
                        maxProperties: 20
                        type: object
                        x-kubernetes-validations:
                          - message: empty tag keys or values aren't supported
                            rule: self.all(k, k != '' && self[k] != '')
                    type: object
                  maxItems: 30
                  type: array
                  x-kubernetes-validations:
                    - message: securityGroupSelectorTerms cannot be empty
                      rule: self.size() != 0
                    - message: expected at least one, got none, ['tags', 'id', 'name']
                      rule: self.all(x, has(x.tags) || has(x.id) || has(x.name))
                    - message: '''id'' is mutually exclusive, cannot be set with a combination of other fields in securityGroupSelectorTerms'
                      rule: '!self.all(x, has(x.id) && (has(x.tags) || has(x.name)))'
                    - message: '''name'' is mutually exclusive, cannot be set with a combination of other fields in securityGroupSelectorTerms'
                      rule: '!self.all(x, has(x.name) && (has(x.tags) || has(x.id)))'
                subnetSelectorTerms:
                  description: SubnetSelectorTerms is a list of or subnet selector terms. The terms are ORed.
                  items:
                    description: |-
                      SubnetSelectorTerm defines selection logic for a subnet used by Karpenter to launch nodes.
                      If multiple fields are used for selection, the requirements are ANDed.
                    properties:
                      id:
                        description: ID is the subnet id in EC2
                        pattern: subnet-[0-9a-z]+
                        type: string
                      tags:
                        additionalProperties:
                          type: string
                        description: |-
                          Tags is a map of key/value tags used to select subnets
                          Specifying '*' for a value selects all values for a given tag key.
                        maxProperties: 20
                        type: object
                        x-kubernetes-validations:
                          - message: empty tag keys or values aren't supported
                            rule: self.all(k, k != '' && self[k] != '')
                    type: object
                  maxItems: 30
                  type: array
                  x-kubernetes-validations:
                    - message: subnetSelectorTerms cannot be empty
                      rule: self.size() != 0
                    - message: expected at least one, got none, ['tags', 'id']
                      rule: self.all(x, has(x.tags) || has(x.id))
                    - message: '''id'' is mutually exclusive, cannot be set with a combination of other fields in subnetSelectorTerms'
                      rule: '!self.all(x, has(x.id) && has(x.tags))'
                tags:
                  additionalProperties:
                    type: string
                  description: Tags to be applied on ec2 resources like instances and launch templates.
                  type: object
                  x-kubernetes-validations:
                    - message: empty tag keys aren't supported
                      rule: self.all(k, k != '')
                    - message: tag contains a restricted tag matching kubernetes.io/cluster/
                      rule: self.all(k, !k.startsWith('kubernetes.io/cluster') )
                    - message: tag contains a restricted tag matching karpenter.sh/nodepool
                      rule: self.all(k, k != 'karpenter.sh/nodepool')
                    - message: tag contains a restricted tag matching karpenter.sh/managed-by
                      rule: self.all(k, k !='karpenter.sh/managed-by')
                    - message: tag contains a restricted tag matching karpenter.sh/nodeclaim
                      rule: self.all(k, k !='karpenter.sh/nodeclaim')
                    - message: tag contains a restricted tag matching karpenter.k8s.aws/ec2nodeclass
                      rule: self.all(k, k !='karpenter.k8s.aws/ec2nodeclass')
                userData:
                  description: |-
                    UserData to be applied to the provisioned nodes.
                    It must be in the appropriate format based on the AMIFamily in use. Karpenter will merge certain fields into
                    this UserData to ensure nodes are being provisioned with the correct configuration.
                  type: string
              required:
                - amiFamily
                - securityGroupSelectorTerms
                - subnetSelectorTerms
              type: object
              x-kubernetes-validations:
                - message: amiSelectorTerms is required when amiFamily == 'Custom'
                  rule: 'self.amiFamily == ''Custom'' ? self.amiSelectorTerms.size() != 0 : true'
                - message: must specify exactly one of ['role', 'instanceProfile']
                  rule: (has(self.role) && !has(self.instanceProfile)) || (!has(self.role) && has(self.instanceProfile))
                - message: changing from 'instanceProfile' to 'role' is not supported. You must delete and recreate this node class if you want to change this.
                  rule: (has(oldSelf.role) && has(self.role)) || (has(oldSelf.instanceProfile) && has(self.instanceProfile))
            status:
              description: EC2NodeClassStatus contains the resolved state of the EC2NodeClass
              properties:
                amis:
                  description: |-
                    AMI contains the current AMI values that are available to the
                    cluster under the AMI selectors.
                  items:
                    description: AMI contains resolved AMI selector values utilized for node launch
                    properties:
                      id:
                        description: ID of the AMI
                        type: string
                      name:
                        description: Name of the AMI
                        type: string
                      requirements:
                        description: Requirements of the AMI to be utilized on an instance type
                        items:
                          description: |-
                            A node selector requirement is a selector that contains values, a key, and an operator
                            that relates the key and values.
                          properties:
                            key:
                              description: The label key that the selector applies to.
                              type: string
                            operator:
                              description: |-
                                Represents a key's relationship to a set of values.
                                Valid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.
                              type: string
                            values:
                              description: |-
                                An array of string values. If the operator is In or NotIn,
                                the values array must be non-empty. If the operator is Exists or DoesNotExist,
                                the values array must be empty. If the operator is Gt or Lt, the values
                                array must have a single element, which will be interpreted as an integer.
                                This array is replaced during a strategic merge patch.
                              items:
                                type: string
                              type: array
                              x-kubernetes-list-type: atomic
                          required:
                            - key
                            - operator
                          type: object
                        type: array
                    required:
                      - id
                      - requirements
                    type: object
                  type: array
                conditions:
                  description: Conditions contains signals for health and readiness
                  items:
                    description: Condition aliases the upstream type and adds additional helper methods
                    properties:
                      lastTransitionTime:
                        description: |-
                          lastTransitionTime is the last time the condition transitioned from one status to another.
                          This should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.
                        format: date-time
                        type: string
                      message:
                        description: |-
                          message is a human readable message indicating details about the transition.
                          This may be an empty string.
                        maxLength: 32768
                        type: string
                      observedGeneration:
                        description: |-
                          observedGeneration represents the .metadata.generation that the condition was set based upon.
                          For instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date
                          with respect to the current state of the instance.
                        format: int64
                        minimum: 0
                        type: integer
                      reason:
                        description: |-
                          reason contains a programmatic identifier indicating the reason for the condition's last transition.
                          Producers of specific condition types may define expected values and meanings for this field,
                          and whether the values are considered a guaranteed API.
                          The value should be a CamelCase string.
                          This field may not be empty.
                        maxLength: 1024
                        minLength: 1
                        pattern: ^[A-Za-z]([A-Za-z0-9_,:]*[A-Za-z0-9_])?$
                        type: string
                      status:
                        description: status of the condition, one of True, False, Unknown.
                        enum:
                          - \"True\"
                          - \"False\"
                          - Unknown
                        type: string
                      type:
                        description: type of condition in CamelCase or in foo.example.com/CamelCase.
                        maxLength: 316
                        pattern: ^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?(([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])$
                        type: string
                    required:
                      - lastTransitionTime
                      - message
                      - reason
                      - status
                      - type
                    type: object
                  type: array
                instanceProfile:
                  description: InstanceProfile contains the resolved instance profile for the role
                  type: string
                securityGroups:
                  description: |-
                    SecurityGroups contains the current Security Groups values that are available to the
                    cluster under the SecurityGroups selectors.
                  items:
                    description: SecurityGroup contains resolved SecurityGroup selector values utilized for node launch
                    properties:
                      id:
                        description: ID of the security group
                        type: string
                      name:
                        description: Name of the security group
                        type: string
                    required:
                      - id
                    type: object
                  type: array
                subnets:
                  description: |-
                    Subnets contains the current Subnet values that are available to the
                    cluster under the subnet selectors.
                  items:
                    description: Subnet contains resolved Subnet selector values utilized for node launch
                    properties:
                      id:
                        description: ID of the subnet
                        type: string
                      zone:
                        description: The associated availability zone
                        type: string
                      zoneID:
                        description: The associated availability zone ID
                        type: string
                    required:
                      - id
                      - zone
                    type: object
                  type: array
              type: object
          type: object
      served: true
      storage: true
      subresources:
        status: {}
{{- if .Values.webhook.enabled }} 
  conversion:
    strategy: Webhook
    webhook:
      conversionReviewVersions:
        - v1beta1
        - v1
      clientConfig:
        service:
          name: {{ .Values.webhook.serviceName }}
          namespace: {{ .Values.webhook.serviceNamespace | default .Release.Namespace }}
          port: {{ .Values.webhook.port }}
{{- end }}
" >>  charts/karpenter-crd/templates/karpenter.k8s.aws_ec2nodeclasses.yaml
