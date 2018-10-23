# Docksal Sandbox Server - AWS CloudFormation

This is a Docksal Sandbox Server template for AWS CloudFormation.

AWS CloudFormation is a service that helps you model and set up your Amazon Web Services resources so that you
can spend less time managing those resources and more time focusing on your applications that run in AWS.
You create a template that describes all the AWS resources that you want (like Amazon EC2 instances or Amazon RDS
DB instances), and AWS CloudFormation takes care of provisioning and configuring those resources for you. You
don't need to individually create and configure AWS resources and figure out what's dependent on what;
AWS CloudFormation handles all of that. 

For an overview of AWS CloudFormation, see https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html.

## Quick setup (using CloudFormation web UI)

If you have an existing AWS account (with billing and an SSH key pair), just click on the button below!

[![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://console.aws.amazon.com/cloudformation/home#/stacks/new?stackName=docksal-sandbox-server&templateURL=https://s3.us-east-2.amazonaws.com/docksal-aws-templates/sandbox-server/stable/template.yaml)

You will be prompted for:

- Instance type
- SSH key name

Once provisioned, the IP address of the server will be printed in the **Outputs** section in CloudFormation. 


## Manual setup (using console tools)  

Step-by-step manual setup instructions using aws cli and provisioning scripts. 

### Initial setup on AWS CloudFormation

1. Log in or create a new AWS account.

1. [Create Access Keys for Your AWS Account Root User](https://docs.aws.amazon.com/general/latest/gr/managing-aws-access-keys.html). Keep these keys in a safe place!

1. [Create SSH key pair or import existing key pair](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair). Or you can use the `ssh-key-create/ssh-key-import` scripts in this repo.

1. Install on you local PC aws cli tool (for ubuntu run `sudo apt install awscli`)

1. Clone this repo

1. Configure `aws` tool to use your account.

    ```
    aws configure
    ```

### Creating SSH key pair and import to AWS EC2

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

By default create-stack script use template.yaml. If you want using template in json format you can edit
create-stack script and change the value of the `template_file` variable to the preferred template format.

Launch the deployment:

    ./create-stack <stack-name> <keyname> [<instancetype>]

In the output of the command you'll find the server public IP address:

    InstanceIPAddress <external-ip>

### Access the sandbox server

SSH into the server and switch to the `build-agent` user:

    ssh ubuntu@<external-ip> -i .ssh/<keyname>
    sudo su - build-agent

Docksal is installed under the `build-agent` user account on the server. Sandbox builds MUST run as this user.

### Delete the sandbox server

To delete the deployment and all the resources that were created:

    ./delete-stack <stack-name>
