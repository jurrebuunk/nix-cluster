---
icon: lucide/user-plus
---

# Create an S3 user

Give an application its own S3 credentials and bucket on
`https://s3.lan.buunk.org`. Background: [S3 endpoint](../concepts/s3.md).

## Before you start

- SSH to a host.
- A client on the storage VLAN for the bucket step: a VM, a pod, or the
  laptop through an [SSH forward](../concepts/s3.md#from-the-laptop).

S3 credentials are separate from Ceph keys and SSH logins. Give every app its
own user; don't share my personal `jurre` user (its keys are root-only on hv01
in `/root/jurre-s3-credentials.json`).

## Steps

1. **Create the user** on any host, writing the keys straight to a root-only
   file:

    ```sh
    ssh jurre@10.10.20.11
    sudo sh -c 'umask 077; radosgw-admin user create --uid=my-app \
      --display-name="My application" > /root/my-app-s3-credentials.json'
    ```

2. **Hand the keys to the app** through its secret handling (a Kubernetes
   Secret through sops in `hgd1-k8s`, or an agenix secret here). Never paste them
   into chat, logs or Git.
3. **Configure a client** and create a bucket:

    ```sh
    aws configure --profile my-app                     # keys from the file, region us-east-1
    aws configure set s3.addressing_style path --profile my-app
    aws --profile my-app --endpoint-url https://s3.lan.buunk.org s3 mb s3://my-bucket
    ```

## Check it worked

```sh
aws --profile my-app --endpoint-url https://s3.lan.buunk.org s3 ls
```

## Good to know

- Path-style addressing only; wildcard bucket names aren't configured.
- Bucket names are global within this object store.
- Rotate keys with `radosgw-admin key create --uid=my-app`, then remove the
  old key once the app uses the new one.
