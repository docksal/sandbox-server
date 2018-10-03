{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Description" : "Sandbox server template",

  "Parameters" : {
    "KeyName": {
      "Description" : "Name of an existing EC2 KeyPair to enable SSH access to the instance",
      "Type": "AWS::EC2::KeyPair::KeyName",
      "ConstraintDescription" : "must be the name of an existing EC2 KeyPair."
    },
    "InstanceType" : {
      "Description" : "EC2 instance type",
      "Type" : "String",
      "Default" : "t2.micro",
      "AllowedValues" : [ "t1.micro", "t2.nano", "t2.micro", "t2.small", "t2.medium", "t2.large", "t3.nano", "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "t3.xlarge", "t3.2xlarge", "m1.small", "m1.medium", "m1.large", "m1.xlarge", "m2.xlarge", "m2.2xlarge", "m2.4xlarge", "m3.medium", "m3.large", "m3.xlarge", "m3.2xlarge", "m4.large", "m4.xlarge", "m4.2xlarge", "m4.4xlarge", "m4.10xlarge", "c1.medium", "c1.xlarge", "c3.large", "c3.xlarge", "c3.2xlarge", "c3.4xlarge", "c3.8xlarge", "c4.large", "c4.xlarge", "c4.2xlarge", "c4.4xlarge", "c4.8xlarge", "g2.2xlarge", "g2.8xlarge", "r3.large", "r3.xlarge", "r3.2xlarge", "r3.4xlarge", "r3.8xlarge", "i2.xlarge", "i2.2xlarge", "i2.4xlarge", "i2.8xlarge", "d2.xlarge", "d2.2xlarge", "d2.4xlarge", "d2.8xlarge", "hi1.4xlarge", "hs1.8xlarge", "cr1.8xlarge", "cc2.8xlarge", "cg1.4xlarge"],
      "ConstraintDescription" : "must be a valid EC2 instance type."
    }
  },

  "Mappings" : {
    "Region2AMI" : {
      "ap-south-1" : { "AMI" : "ami-0d773a3b7bb2bb1c1" },
      "eu-west-3" : { "AMI" : "ami-08182c55a1c188dee" },
      "eu-west-2" : { "AMI" : "ami-0b0a60c0a2bd40612" },
      "eu-west-1" : { "AMI" : "ami-00035f41c82244dab" },
      "ap-northeast-2" : { "AMI" : "ami-06e7b9c5e0c4dd014" },
      "ap-northeast-1" : { "AMI" : "ami-07ad4b1c3af1ea214" },
      "sa-east-1" : { "AMI" : "ami-03c6239555bb12112" },
      "ca-central-1" : { "AMI" : "ami-0427e8367e3770df1" },
      "ap-southeast-1" : { "AMI" : "ami-0c5199d385b432989" },
      "ap-southeast-2" : { "AMI" : "ami-07a3bd4944eb120a0" },
      "eu-central-1" : { "AMI" : "ami-0bdf93799014acdc4" },
      "us-east-1" : { "AMI" : "ami-0ac019f4fcb7cb7e6" },
      "us-east-2" : { "AMI" : "ami-0f65671a86f061fcd" },
      "us-west-1" : { "AMI" : "ami-063aa838bd7631e0b" },
      "us-west-2" : { "AMI" : "ami-0bbe6b35405ecebdb" }
    }
  },

  "Resources" : {
    "InstanceSecurityGroup" : {
      "Type" : "AWS::EC2::SecurityGroup",
      "Properties" : {
        "GroupDescription" : "Enable SSH, HTTP, HTTPS",
        "SecurityGroupIngress" : [
          {
          "IpProtocol" : "tcp",
          "FromPort" : "22",
          "ToPort" : "22",
          "CidrIp" : "0.0.0.0/0"
          },
          {
          "IpProtocol" : "tcp",
          "FromPort" : "80",
          "ToPort" : "80",
          "CidrIp" : "0.0.0.0/0"
          },
          {
          "IpProtocol" : "tcp",
          "FromPort" : "443",
          "ToPort" : "443",
          "CidrIp" : "0.0.0.0/0"
          }]
      }
    },
    "IPAddress" : {
      "Type" : "AWS::EC2::EIP"
    },

    "IPAssoc" : {
      "Type" : "AWS::EC2::EIPAssociation",
      "Properties" : {
        "InstanceId" : { "Ref" : "EC2Instance" },
        "EIP" : { "Ref" : "IPAddress" }
      }
    },

    "EC2Instance" : {
      "Type" : "AWS::EC2::Instance",
      "Properties" : {
        "InstanceType" : { "Ref" : "InstanceType" },
	"ImageId" : { "Fn::FindInMap" : [ "Region2AMI", { "Ref" : "AWS::Region" }, "AMI" ]},
	"KeyName" : { "Ref" : "KeyName" },
	"SecurityGroups" : [ { "Ref" : "InstanceSecurityGroup" } ],
        "BlockDeviceMappings" : [
          {
            "DeviceName" : "/dev/sda1",
            "Ebs" : { "VolumeSize" : "8" } 
          },{
            "DeviceName" : "/dev/sdp",
            "Ebs" : { "VolumeSize" : "100" }
          }
        ],
	"UserData" : { "Fn::Base64" : { "Fn::Join" : [ "", [


	]]}}
      }
    }
  },
  "Outputs" : {
    "InstanceID" : {
      "Value" : { "Ref" : "EC2Instance" }
    },
    "InstanceIPAddress" : {
      "Value" : { "Ref" : "IPAddress" }
    }
  }
}
