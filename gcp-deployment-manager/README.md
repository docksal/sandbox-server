# Docksal Sandbox Server - GCP Deployment Manager

This is a Docksal Sandbox Server template for Google Cloud Deployment Manager.

Google Cloud Deployment Manager is an infrastructure management service that makes it simple to create, deploy,
and manage Google Cloud Platform resources. With Deployment Manager, you can create a static or dynamic template
that describes the configuration of your Google Cloud environment and then use Deployment Manager to create these
resources as a single or collection of deployments.

For an overview of Deployment Manager, see https://cloud.google.com/deployment-manager/docs.

## Initial setup on GCP

1. Select or create a Cloud Platform project, [from the Manage Resources page](https://console.cloud.google.com/cloud-resource-manager).

1. [Enable billing](https://support.google.com/cloud/answer/6293499#enable-billing).

1. [Enable the Deployment Manager and Compute APIs](https://console.cloud.google.com/flows/enableapi?apiid=deploymentmanager,compute_component).

1. Setup SSH keys.

1. Proceed with Local setup below.

1. Deploy the sandbox.

### Set up SSH keys in the GCP project

Generate a new SSH key pair:

    ssh-keygen -t ecdsa -q -N "" -f ~/.ssh/<keyname> -C build-agent@docksal-sandbox

Replace `<keyname>` with something meaningful to identify the key, e.g. `docksal-sandbox-server`.

**Note**: The `-C build-agent@docksal-sandbox` part is important.

GCP uses the comment in the key to map the key to a Linux user. It will update the `build-agent` user's
`~/.ssh/authorized_keys` automatically, when you follow the steps below.

View and copy the public key:

    cat ~/.ssh/<keyname>.pub

Use the copied string to set a [project-wide](https://cloud.google.com/compute/docs/instances/adding-removing-ssh-keys#project-wide) public SSH key on GCP.

### Local Setup

You must have Docker installed. Local setup uses the image `google/cloud-sdk`. See the [image's Docker Hub page](https://hub.docker.com/r/google/cloud-sdk) for additional details on using this image.

1. Run `make login`. This will ask you to copy/paste a URL into your browser and copy/paste a token. See [`gcloud auth login`](https://cloud.google.com/sdk/gcloud/reference/auth/login) for additional details.

1. Run `make bash` for container CLI and run `gcloud config set project <project-id>`. Future `make`  commands will automatically run with the context of your project.

### Deploying the sandbox

After deployment you will have the following resources requisitioned (resources you pay for denoted by ($)):

- VM instance (defaults to preemptible) ($)
- Standard disk (150GB default) ($)
- Static IP address ($)
- Managed instance group
- VM instance template

Assuming you have already logged in and set the project as directed above, you simply need to run the following to setup your sandbox:

    make create

Then, in your GCP Console:

1. navigate to Compute Engine > VM instances.
1. Find the IP address assigned to your VM.
1. Log into your VM via `build-agent@x.x.x.x`, where x.x.x.x is the IP identified in step 2.
1. Run `fin system status`. If the Docksal system containers all appear as `Up` then everything is ready to go.
1. If the Docksal system status is either not returned, or you get an error of some kind, you will want to: log out, wait a few minutes, then log back in. Run `fin system status` again and it should come back as up.

**NOTE**: You will want to wait ~5 minutes after running `make create` to ensure the VM has had time to fully assemble itself. This is only true for first time setups.

## Managing user access to the machine

You can associate multiple SSH keys with the project to control user access, see [working with SSH keys](https://cloud.google.com/compute/docs/instances/adding-removing-ssh-keys) for details on how to add and remove SSH keys from the project.

Project SSH keys, and their associated user, are automatically added to all VM instances in your project. If you add an SSH key to the project metadata with user id `user-a`, then after the machine has been provisioned, or restarted, that user will be able to login to the machine via `ssh user-a@x.x.x.x` where `x.x.x.x` is the sandbox VM's IP address.

### Running commands as `build-agent`

Sandboxes are stored in `/home/build-agent/builds`. Therefore, if you need to interact with a sandbox, you must be the user `build-agent`. All users with project-level SSH keys have passwordless sudo access. So, if you are logging into the machine as a user besides `build-agent`, to interact with the builds you must do the following:

1. Run `ssh my-user-id@x.x.x.x`.
1. Run `sudo -s` to assume root.
1. Run `su - build-agent`.

## Customizing VM instance properties

Reasonable defaults are assigned to the sandbox server out of the box:

| Property     | Value         |
|--------------|---------------|
| Machine size | n1-standard-2 |
| Disk size    | 150GB         |
| Preemptible  | true          |
| Region       | us-east4      |
| Zone         | us-east4-c    |

These properties are represented in `project.env`. You may override these values in one of two files: `project-override.env` and `local-override.env`. `project-override.env` is intended to be a version controlled file. `local-override.env` is, conversely, not version controlled. The files are included in the `Makefile` in the following order:

1. project.env
1. project-override.env
1. local-override.env

This project supports the customization of the following variables:

1. `ZONE` - See [Regions and Zones](https://cloud.google.com/compute/docs/regions-zones) for acceptable values.
1. `REGION` - See [Regions and Zones](https://cloud.google.com/compute/docs/regions-zones) for acceptable values.
1. `DEFAULT_MACHINE_SIZE` - See [Machine Types](https://cloud.google.com/compute/docs/machine-types) for the various types of machines you can use. We have found that the `n1-standard` series provides optimum computing power for sandbox purposes.
1. `DISK_SIZE` - the size of the machine in GB (integer only).
1. `TEMPLATE_ID` - unique identifier for a template. If any other properties of the template changes, you MUST change the template ID as well. You will most frequently need to change this if you decide to toggle the instance's preemptive setting.
1. `PREEMPTIVE` - (boolean) true or false. Determines whether or not a machine should be preemptive. Preemptive machines are far cheaper, and the uptime is usually adequate enough as to not provide disruptions to your daily operations. See [Preemptible VM instances](https://cloud.google.com/compute/docs/instances/preemptible) for more information.

**NOTE:** Never surround the values of overridden variables with quotes. Reference `project.env` for the proper way to format values.

### Examples

Lets say you need a bigger disk and a bigger machine than comes standard. You'll want:

1. Add `project-override.env` and set its contents to:

        DEFAULT_MACHINE_SIZE=n1-standard-4
        DISK_SIZE=250

1. Run `make create`. That will create a sandbox server with machine type `n1-standard-4` instead of `n1-standard-2` and a disk with size `250GB` instead of `150GB`.

If you have already created the sandbox instance and you need to upsize the machine because you are running more active sandboxes, you should:

1. Update/create `project-override.env` to include:

    - A bigger machine size.
    - A DIFFERENT value for TEMPLATE_ID. This is because the machine size is a property of the instance template, and GCP does not allow updating properties of a template. A NEW template must be created with the new values. The `Makefile` handles this for you automatically, but you DO need to set a `TEMPLATE_ID` value that is different from what was last deployed.

        Note that, any updates to the following variables requires you also update the current value of `TEMPLATE_ID` to something different:

        - ZONE
        - PREEMPTIVE
        - DEFAULT_MACHINE_SIZE

1. With the above in mind, lets say the current machine type is `n1-standard-4`, and you want to upsize it to `n1-standard-8` to get more processors and memory. Update `project-override.env` to look like:

        DEFAULT_MACHINE_SIZE=n1-standard-8
        TEMPLATE_ID=custom-docksal-sandbox-template-002

1. Run `make update`. If you forget to change `TEMPLATE_ID` to a new, unique, value, then `make update` will error.

1. Observe the GCP Console and verify that your machine size has been updated. If there is a sandbox site present on the server, visit its sandbox URL to verify that the site is still functioning.

The machine instance is intended to be stateless, but the disk is stateful. So, you can recreate the machine instance as many times as you'd like, but it will keep using the same data disk which preserves all of the existing sandboxes and settings in the `build-agent` home directory.
