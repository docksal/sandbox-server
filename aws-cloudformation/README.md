# Docksal Sandbox Server - AWS CloudFormation

This is a Docksal Sandbox Server template for AWS CloudFormation.

AWS CloudFormation is a service that helps you model and set up your Amazon Web Services resources so that you
can spend less time managing those resources and more time focusing on your applications that run in AWS.
You create a template that describes all the AWS resources that you want (like Amazon EC2 instances or Amazon RDS
DB instances), and AWS CloudFormation takes care of provisioning and configuring those resources for you. You
don't need to individually create and configure AWS resources and figure out what's dependent on what;
AWS CloudFormation handles all of that. 

For an overview of AWS CloudFormation, see the [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html.)

<a name="features"></a>
## Features

- Turn-key AWS infrastructure provisioning using CloudFormation
- Basic mode: very few questions asked, quick and easy
  - [Smart resource management](#smart-resource-management)
  - [Data persistence](#data-persistence)
  - [IP persistence](#ip-persistence)
- Advanced mode: includes basic + all advanced settings and features
  - [EC2 Spot mode support](#spot)
  - [LetsEncrypt integration](#letsencrypt)
  - [Attached S3 storage](#s3)
  - [Deploy into a custom VPC](#vpc)
  - [Access restriction by IP range](#access-ip)
  - [Manage SSH access via Github org/team](#access-ssh)


<a name="basic"></a>
## Basic mode: Quick setup (using CloudFormation web UI)

If you have an existing AWS account (with billing and an SSH key pair), just click on the button below!

**WARNING:** if you have an existing sandbox server created before Dec 31, 2019 (v1), **DO NOT UPGRADE**.  
See [v2.0.0](https://github.com/docksal/sandbox-server/releases/tag/v2.0.0) release notes.

[![Launch Basic Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://console.aws.amazon.com/cloudformation/home#/stacks/new?stackName=docksal-sandbox-server&templateURL=https://docksal-aws-templates.s3.us-east-2.amazonaws.com/sandbox-server/v3.3.0/basic.json) (v3.3.0)

You will be prompted for:

- Instance type
- SSH key name
- Data disk size

Once provisioned, the IP address of the server will be printed in the **Outputs** section in CloudFormation (`<external-ip>`). 

Note: You will need the key you selected to access the sandbox server in further steps (`<ssh-private-key>`).

You can now proceed to [Access the sandbox server](/README.md#server-access) 

Note: For manual setup steps (using console tools), see [Manual setup](#manual)

<a name="advanced"></a>
## Advanced mode: Quick setup (using CloudFormation web UI)

If you have an existing AWS account (with billing and an SSH key pair), just click on the button below!

**WARNING:** if you have an existing sandbox server created before Dec 31, 2019 (v1), **DO NOT UPGRADE**.  
See [v2.0.0](https://github.com/docksal/sandbox-server/releases/tag/v2.0.0) release notes.

[![Launch Advanced Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://console.aws.amazon.com/cloudformation/home#/stacks/new?stackName=docksal-sandbox-server&templateURL=https://docksal-aws-templates.s3.us-east-2.amazonaws.com/sandbox-server/v3.3.0/advanced.json) (v3.3.0)

You will be prompted for a few required and optional settings.

- Basic: Required
  - Resource type (`ec2` vs `spot`)
  - Instance architecture (`amd64` vs `arm64`)
  - Instance type (primary)
  - Instance type 2 (`spot` mode only)
  - SSH key
  - Availability zone
- VPC/Network: Optional
  - VPC ID
  - Subnet ID
  - Elastic IP
  - Access from CIDR 1
  - Access from CIDR 2
  - Access from CIDR 3
  - Security Group ID 1
  - Security Group ID 2
  - Security Group ID 3
- Storage: Optional
  - Persistent data volume
  - Enable artifacts bucket
  - Artifacts bucket name
- Github settings: Optional - used for SSH authentication via GitHub org/team
  - Github token
  - Github organization
  - Github team
- LetsEncrypt settings: Optional
  - Sandbox domain name
  - LetsEncrypt configuration
- Docksal settings: Optional
  - Docksal version

Once provisioned, the IP address of the server will be printed in the **Outputs** section in CloudFormation (`<external-ip>`). 

Note: You will need the key you selected to access the sandbox server in further steps (`<ssh-private-key>`).

You can now proceed to [Access the sandbox server](/README.md#server-access) 


<a name="features-details"></a>
## Features details

<a name="smart-resource-management"></a>
### Smart resource management

On a sandbox server, you will be running lots of builds and Docksal project stacks. If left unmanaged, these stacks will 
deplete the server resources eventually. 

One way to control the number of running sandbox environments is via CI/CD automation. You can have a feature branch 
environment stopped/removed from the sandbox server upon PR/MR merge or when the feature branches is deleted from git. 
This approach requires some manual setup work in your CI/CD pipeline and is not mandatory with `docksal/sandbox-server`.

`docksal/sandbox-server` utilized advanced features in [docksal/vhosts-proxy](https://github.com/docksal/service-vhost-proxy#advanced-proxy-configuration) 
to enabled smart resource management.

Out of the box:

- After 0.5h or inactivity, project stacks are stopped to free up CPU and RAM resources.
- After 7 days of inactivity, project stacks are are removed from the server entirely (freeing up disk space as well).
- An HTTP/HTTPS request to an existing but stopped environment on the server will wake up the environment auto-magically!

Note: there is a hard limit of roughly 30 stacks that can be active at a time on a sandbox server. In reality, it's 
unlikely that this limit will be reached on a typical sandbox server.

<a name="data-persistence"></a>
### Data persistence

Data in the `build-agent` user's home (`/home/build-agent`) and anything managed in Docker (`/var/lib/docker`) 
is mounted from an attached EBS data volume. This allows **re-creating or resizing the instance at any time without data 
loss**.

Note: data outside of these two locations is ephemeral. It will persist on instance restarts, but will be lost upon 
instance re-creation. Do not rely on manually installed packages. Instead, use Docker and run any extra workloads 
on the sandbox server (e.g., a Jenkins instance) in containers.

An EBS data volume is automatically created and attached to the sandbox server instance.

Basic template allows settings the volume size in the template parameters.   

Advanced template allows to specify an existing (manually created) EBS volume. The existing volume can be empty or can 
be from a previously running sandbox server instance. 

<a name="ip-persistence"></a>
## IP persistence

An Elastic IP is automatically provisioned and reused when an instance is re-created or re-sized.

In the advanced template, it is possible to specify an existing manually allocated Elastic IP.

<a name="spot"></a>
### EC2 Spot mode

This feature is available in the [advanced template](#advanced) only.

Using [AWS EC2 Spot instances](https://aws.amazon.com/ec2/spot/) can save up to 90% of EC2 compute costs. 
If an occasional (once in a few months or even less) instance downtime of 5-10 minutes is acceptable, then it's a 
no-brainer option.

This template is built to be fault-tolerant and compatible with the AWS Spot mode. When the spot instance is recycled, 
the EBS data volume and ElasticIP are re-attached back to the new instance.

If your workloads require guaranteed server uptime (e.g., you are running your CI/CD instance in a container on the 
sandbox server), then opt for the `ec2` (on-demand) mode in the template settings. Both templates (basic and advanced) 
default to using the `ec2` (on-demand) mode.

Icing on the cake: you can switch the modes at any time via the template parameters without data loss!  
Note: Make sure to configure a persistent data volume to avoid data loss in spot mode.

<a name="letsencrypt"></a>
### LetsEncrypt integration

This feature is available in the [advanced template](#advanced) only.

`docksal/sandbox-server` uses the [acme.sh](https://github.com/Neilpang/acme.sh) ACME client to interact with LetsEncrypt.

The are two settings to configure:

**Sandbox domain name**

Domain name for which a wildcard LetsEncrypt certificate will be issued.
E.g., for `example.com`, an SNI wildcard cert will be issued covering both `example.com` and `*.example.com`.

**LetsEncrypt configuration**

Configuration for automated LetsEncrypt certificate provisioning (space delimited `variable="value"` pairs).  
Info about available options: https://github.com/Neilpang/acme.sh/wiki/dnsapi.  
Example: `DSP="dns_aws" AWS_ACCESS_KEY_ID="aws_access_key_id" AWS_SECRET_ACCESS_KEY="aws_secret_key"`.  

Note: If the sandbox domain is managed in AWS Route53 in the same AWS account, then leave this field empty to give 
the server the necessary permissions to managed `TXT` records in Route53. This is the easiest and the recommended way.

<a name="s3"></a>
### Attached S3 storage

This feature is available in the [advanced template](#advanced) only.

An AWS S3 bucket is provisioned and mounted using [s3fs](https://github.com/s3fs-fuse/s3fs-fuse) in 
`/home/build-agent/artifacts`.

This gives a cheap persistent data storage alternative to using the ESB data volume (mounted in `/data` on the server) 
to store artifacts, backups, etc.

<a name="vpc"></a>
### Deploy into a custom VPC

This feature is available in the [advanced template](#advanced) only.

Allows specifying the custom VPC ID and Subnet ID where the server will be attached.

<a name="access-ip"></a>
### Access restriction by IP range (CIDR)

This feature is available in the [advanced template](#advanced) only.

Restricts access to the sandbox server instance (ports `22`, `80`, `443`) by IP range (CIDR).

Defaults to `0.0.0.0/0` (unrestricted access). Supports up to 3 CIDRs.

<a name="security-group"></a>
### Attach a custom Security Group

This feature is available in the [advanced template](#advanced) only.

Allows specifying up to 3 existing Security Groups (ingress/egress firewall rules) for the sandbox server instance.

Can be used instead of or in conjunction with the IP based ingress restrictions (see above).

<a name="access-ssh"></a>
### Manage SSH access via Github org/team

This feature is available in the [advanced template](#advanced) only.

Allows SSH authentication with the server via Github org/team using [lmakarov/ssh-rake](https://github.com/lmakarov/ssh-rake).

Very handy when you use Github for you team and want to allow multiple team members to SSH into the sandbox server.  


<a name="manual"></a>
## Basic mode: Manual setup (using console tools)

Step-by-step manual setup instructions using aws cli and provisioning scripts. 

### Initial setup on AWS

1. Log in or create a new AWS account.

1. [Create Access Keys for Your AWS Account Root User](https://docs.aws.amazon.com/general/latest/gr/managing-aws-access-keys.html). Keep these keys in a safe place!

1. [Create SSH key pair or import existing key pair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair).
 
    **Note**: You can also use the `ssh-key-create` / `ssh-key-import` scripts in this repo (see instructions below).

1. Install `aws` cli tool locally (for Ubuntu run `sudo apt install awscli`)

1. Clone this repo

1. Configure `aws` cli tool to use your account

    ```
    aws configure
    ```

### Create SSH key pair and import the key to AWS EC2

**Note**: Skip this step, if you already have an existing SSH key pair or created one earlier in this process.

Navigate to the `aws-cloudformation` folder:

    cd aws-cloudformation

Execute:

    ./scripts/ssh-key-create <keyname> - this will create new SSH key pair in your ~/.ssh directory
    ./scripts/ssh-key-import <keyname> - this will import a local SSH key pair to all AWS EC2 regions

### Deploy the sandbox server

Navigate to the `aws-cloudformation` folder:

    cd aws-cloudformation

Create template ready for deploy:

    ./scripts/bash2yaml startup.sh - will create template file template.yaml with startup.sh merged in it
    ./scripts/bash2json startup.sh - will create template file template.json with startup.sh merged in it

By default create-stack script uses `template.yaml`. If you want using template in json format you can edit
`create-stack` script and change the value of the `template_file` variable to the preferred template format.

Launch the deployment:

    ./create-stack <stack-name> <keyname> [<instancetype>]

In the output of the command you'll find the server public IP address:

    InstanceIPAddress <external-ip>

You can now proceed to [Access the sandbox server](/README.md#server-access)

### Delete the sandbox server

To delete the deployment and all the resources that were created:

    ./delete-stack <stack-name>
