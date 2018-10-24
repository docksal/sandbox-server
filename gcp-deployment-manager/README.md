# Docksal Sandbox Server - GCP Deployment Manager

This is a Docksal Sandbox Server template for Google Cloud Deployment Manager.

Google Cloud Deployment Manager is an infrastructure management service that makes it simple to create, deploy, 
and manage Google Cloud Platform resources. With Deployment Manager, you can create a static or dynamic template 
that describes the configuration of your Google Cloud environment and then use Deployment Manager to create these 
resources as a single deployment.

For an overview of Deployment Manager, see https://cloud.google.com/deployment-manager/docs.

## Initial setup on GCP

1. Select or create a Cloud Platform project, [from the Manage Resources page](https://console.cloud.google.com/cloud-resource-manager).

1. [Enable billing](https://support.google.com/cloud/answer/6293499#enable-billing).

1. [Enable the Deployment Manager and Compute APIs](https://console.cloud.google.com/flows/enableapi?apiid=deploymentmanager,compute_component).

1. Clone this repo

    Clone this repository locally or with [Cloud Shell](https://cloud.google.com/shell/).  
    With Cloud Shell, you can manage your GCP project and resources without installing anything.

    [![Open in Cloud Shell](http://gstatic.com/cloudssh/images/open-btn.svg)](https://console.cloud.google.com/cloudshell/open?git_repo=https%3A%2F%2Fgithub.com%2Fdocksal%2Fsandbox-server&page=editor)

1. Configure `gcloud` tool to use your project. Replace `<project-id>` with the project ID

    ```
    gcloud config set project <project-id>
    ```

## Set up SSH keys in the GCP project

Generate a new SSH key pair:

    ssh-keygen -t ecdsa -q -N "" -f ~/.ssh/<keyname> -C build-agent@docksal-sandbox

Replace `<keyname>` with something meaningful to identify the key, e.g. `docksal-sandbox-server`.

**Note**: The `-C build-agent@docksal-sandbox` part is important.

GCP uses the comment in the key to map the key to a Linux user. It will update the `build-agent` user's 
`~/.ssh/authorized_keys` automatically, when you follow the steps below.

View and copy the public key:

    cat ~/.ssh/<keyname>.pub

   **Note**: they key is a single line. If using Cloud Shell, it may break it into multiple lines. If that is the case, you will have yo manually fix the string to be one line.

Use the copied string to set a [project-wide](https://cloud.google.com/compute/docs/instances/adding-removing-ssh-keys#project-wide) public SSH key on GCP.

You can now proceed to [Access the sandbox server](/#server-access)

## Deploy the sandbox server

Navigate to the `gcp-deployment-manager` folder:

    cd gcp-deployment-manager

Launch the deployment:

    gcloud deployment-manager deployments create docksal-sandbox-server --config config.yaml

In the output of the command you'll find the server public IP address:

    OUTPUTS  VALUE
    ip       <external-ip>

There is a startup script that will do server provisioning. It will take 2-5 minutes from this point.


## Delete the sandbox server

To delete the deployment and all the resources that were created:

    gcloud deployment-manager deployments delete docksal-sandbox-server
