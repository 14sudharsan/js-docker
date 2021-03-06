# TIBCO JasperReports&reg; Server with AKS

# Table of contents

1. [Introduction](#introduction)
1. [Prerequisites](#prerequisites)
1. [JasperReports Server Image Installation](#jasperreports-server-image-installation)
1. [Configure and Start the Jaspersoft repository database](#configure-and-start-the-jaspersoft-repository-database)
1. [Configure the JasperReports Server service](#configure-the-jasperreports-server-service)
1. [Launch the JasperReports Server service](#launch-the-jasperreports-server-service)
1. [Logging in to JasperReports Server ](#logging-in-to-jasperreports-server)

# Introduction

These configuration files perform
[declarative configuration](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
with `kubectl apply` to deploy JasperReports Server within Kubernetes (k8s).

These Kubernetes configurations leverage images created via [https://github.com/TIBCOSoftware/js-docker](#https://github.com/TIBCOSoftware/js-docker)
and configuration options for the JasperReports Server containers are defined there.

You must change the environment variables and declarative configuration to fit with your deployment environment,
such as the platform - Docker for Windows/Mac, Minikube, Amazon EKS, Azure AKS, ... -
and how you want to deploy JasperReports Server:
- exposed to the outside world directly: NodePort, Ingress, LoadBalancer
- JasperReports Server repository database location: within or external to Kubernetes
- use of environment variables and volumes
- use of secrets for passwords

This configuration has been certified using
the PostgreSQL 9 database with JasperReports Server 6.4+
and with PostgreSQL 10 for JasperReports Server 7.2+.

Knowledge of Docker, Kubernetes and your infrastructure is required.

For more information about Docker and containers, see the [official documentation for Docker](https://docs.docker.com/).

For more information about Kubernetes, see the [official documentation for Kubernetes](https://kubernetes.io/).

For more information about JasperReports Server, see:
- [Jaspersoft Quick Start](https://www.jaspersoft.com/quick-start).
- [Jaspersoft community](http://community.jaspersoft.com/).

# Prerequisites

The following software is required or recommended:

- [docker-engine](https://docs.docker.com/engine/installation) version 1.18 or higher
- (*required*) TIBCO Jaspersoft&reg; commercial license.
  - Contact your sales representative for information about licensing.
- (*Recommended*) for development - they include Kubernetes:
  - [Docker Desktop for Windows](https://docs.docker.com/docker-for-windows/install/)
  - [Docker Desktop for Mac](https://docs.docker.com/docker-for-mac/install/)
- (*optional*)[kubernetes](https://kubernetes.io/) version 1.10 or higher
- (*optional*) Preconfigured PostgreSQL 9, 10 or 11 database. If you do not currently have a PostgreSQL instance, you can create a PostgreSQL container at run time.

# Build the Kubernetes specific command line image

Build the main `jasperserver-pro:<version>` and `jasperserver-pro-cmdline:<version>` images in the js-docker directory.

In this directory, run:

`docker build -f Dockerfile-cmdline-k8s -t jasperserver-pro-cmdline:k8s-<version> .`

# Configure the JasperReports Server service

By default, this is a basic deployment, standing up a single instance service, exposed to the outside world through a LoadBalancer.
The init-container in the Service, which runs a cmdline image, ensures that the JasperReports Server repository exists and the keystore files are created in the correct volume, prior to the JaspeReports Server web application starts.

- Modify the environment variables as needed: Refer to [JasperReports Server Docker environment variables](https://github.com/TIBCOSoftware/js-docker#docker-run-time-environment-variables)
- It refers to the repository via `DB_HOST`, which in the default configuration is the `postgresql` service within k8s defined above.
- Do k8s level configuration, such as pods, NodePort or LoadBalancer, use of secrets etc.
  - You can set the NodePort the Server will run on or change the network access as you see fit.
- Decide on secrets and volumes below.

# Secrets and Volumes

Your JasperReports Server license is in a secret.

`kubectl create secret generic jasperserver-pro-license --from-file=jasperserver.license=./jasperserver.license`

Use the secret as a volume in both the init and main containers.

```
        volumeMounts:
        - name: license
          mountPath: "/usr/local/share/jasperserver-pro/license"
          readOnly: true

      volumes:
      - name: license
        secret:
          secretName: jasperserver-pro-license
```

See the main [README](https://github.com/TIBCOSoftware/js-docker#configuring_jasperreports_server_with_volumes) for details of other volumes.

# Saving Keystores

JasperReports Server keystore files need to be saved when the repository database is created or the keystore is updated via the js-import and js-export command line tools.
Here are two approaches to keystore storage:
- Using a persistant volume
- Using a Secret

## A Kubernetes Secret for keystore files

Keystore files can be maintained in a Secret. See the `jasperreports-server-k8s-secret.yaml`.
The cmdline:k8s init container or job creates and updates the keystore secret.
Because of this update of the secret, the ClusterRole used by the Service has to have extended privileges.

```
 - apiGroups:
      - ""
    resources:
      - secrets
    resourceNames:
      - jasperserver-pro-jrsks
    verbs:
      - get
      - update
```
You have to create the jasperserver-pro-jrsks secret.

`kubectl create secret generic jasperserver-pro-jrsks`

You can pre-load the keystore files, too, before you run the server or the command line against a new repository database.

`kubectl create secret generic jasperserver-pro-jrsks --from-file=.jrsks=./.jrsks  --from-file=.jrsksp=./.jrsksp`

These secret needs to be mapped as volumes into the containers.
You need to map a volume for configuration files created by the init container. At least:

```
      volumes:
      - name: keystore-files-secret
        secret:
          secretName: jasperserver-pro-jrsks
      - name: jasperserver-pro-volume
        emptyDir: {}
```

And then use the secret with the containers. For the init container, use the cmdline:k8s image.

```
      initContainers:
      - name: init
        image: jasperserver-pro-cmdline:k8s-7.5.0
        env:
          #- name: KEYSTORE_SECRET_NAME
          #  value: "jasperserver-pro-jrsks"

        volumeMounts:

        # have the keystore secret under its own path.
        # init container will maintain the keystore files in 
        # /usr/local/share/jasperserver-pro/keystore
        # and update the secret if needed

        - name: keystore-files-secret
          mountPath: "/usr/local/share/jasperserver-pro-secrets/jasperserver-pro-jrsks"
          readOnly: true

        - name: jasperserver-pro-volume
          mountPath: "/usr/local/share/jasperserver-pro"
          readOnly: false
```

And for the JasperReports Server web application container:

```
      containers:
      - name: jasperserver-pro
        image: jasperserver-pro:7.5.0
        env:

        volumeMounts:
        - name: license
          mountPath: "/usr/local/share/jasperserver-pro-secrets/license"
          readOnly: true

        # web app accesses the keystore secret directly
        - name: keystore-files-secret
          mountPath: "/usr/local/share/jasperserver-pro/keystore"
          readOnly: true

        - name: jasperserver-pro-volume
          mountPath: "/usr/local/share/jasperserver-pro"
          readOnly: true
```

Install the service via: `kubectl apply -f jasperreports-server-k8s-secret.yaml`

## Persistent Volume for the keystore files

Create a persistent volume. See `local-pv.yaml` as an example.
Run via `kubectl apply -f local-pv.yaml`

Review `jasperreports-server-k8s-volume.yaml`

Include the persistent volume in the service.
```
      volumes:
      - name: jasperserver-pro-volume
        persistentVolumeClaim:
          claimName: jasperreports-server-pv-claim
```

And then use the persistent volume with the containers. For the init container, use the base cmdline image.

```
      initContainers:
      - name: init
        image: jasperserver-pro-cmdline:7.5.0
        env:
        volumeMounts:
        - name: jasperserver-pro-volume
          mountPath: "/usr/local/share/jasperserver-pro"
          readOnly: false
```

for the web application:

```
      containers:
      - name: jasperserver-pro
        image: jasperserver-pro:7.5.0
        env:
        ports:
        volumeMounts:
        - name: jasperserver-pro-volume
          mountPath: "/usr/local/share/jasperserver-pro"
          readOnly: true
```

# Additional environment variables

For the cmdline:

| Environment Variable Name | Notes |
| ------------ | ------------- |
| `KEYSTORE_SECRET_NAME` | When using a secret to store the keystore files, this is the secret name where keystore files will be stored. Used in volumeMount paths. Default: jasperserver-pro-jrsks | 

# Configure and Start the Jaspersoft repository database

This JasperReports Server deloyment to Docker and k8s uses a PostgreSQL database to store configuration information.

You can run the repository outside k8s.
- You will need to set the DB_\* environment variables in the k8s configuration to point to the external database.

Or run the PostgreSQL repository inside k8s, which is the default approach taken with this configuration.
- edit `postgres-k8s.yml` to suit your environment.
  - This creates a persistent volume and the `postgresql` service in k8s 
  - set volume name, username, password, use secrets etc according to your requirements
- use kubectl to create the postgresql service: `kubectl apply -f postgres-k8s.yaml`

See the main README for details on how to use other databases for the repository apart from PostgreSQL.

# Launch the JasperReports Server service

Apply the service via:
- Keystore in secret: `kubectl apply -f jasperreports-server-k8s-secret.yaml`
- Keystore in volume: `kubectl apply -f jasperreports-server-k8s-volume.yaml`

# Troubleshooting

When running the service with keystore files in a secret, this error:
`Error from server (Forbidden): secrets \"jasperserver-pro-jrsks\" is forbidden: User "system:serviceaccount:default:default" cannot get secrets in the namespace "default"`
comes from the cmdline init-container not having permissions to update the secret. See the ClusterRole update above.

# Logging in to JasperReports Server 

After the JasperReports Server container is up, log into it via URL from a browser.

If you launched the service using type: NodePort, you can find the port via:
```
PS > kubectl get services
NAME                   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
jasperreports-server   NodePort    10.96.1.127    <none>        8080:31562/TCP   3m
kubernetes             ClusterIP   10.96.0.1      <none>        443/TCP          1d
postgresql             ClusterIP   10.100.26.80   <none>        5432/TCP         4m
```

31562 indicated above is the NodePort for the jasperreports-server service in the PORT(S) column.

So login via: `http://<host>:<NodePort>/jasperserver-pro`

Where:

- host : name or IP address of your k8s cluster.
- NodePort : NodePort the jasperreports-server service is running on.

JasperReports Server ships with the following default credentials:

- superuser/superuser - System-wide administrator
- jasperadmin/jasperadmin - Administrator for the default organization

# Copyright
Copyright &copy; 2019-2020. TIBCO Software Inc.
This file is subject to the license terms contained
in the license file that is distributed with this file.
___

TIBCO, Jaspersoft, and JasperReports are trademarks or
registered trademarks of TIBCO Software Inc.
in the United States and/or other countries.

Docker is a trademark or registered trademark of Docker, Inc.
in the United States and/or other countries.
