---
icon: lucide/user-plus
---

# Create an S3 user

Give an application its own S3 credentials and bucket on
`https://s3.lan.buunk.org`. Background: [S3 endpoint](../concepts/s3.md).

## Before you start

- A `labctl` token with `manage` scope ([Use the CLI](use-the-cli.md)).
- To use the bucket: a client on the storage VLAN (a VM, a pod, or the
  laptop through an [SSH forward](../concepts/s3.md#from-the-laptop)).

S3 credentials are separate from Ceph keys and SSH logins. Give every app its
own user; don't share my personal `jurre` user.

## Steps

1. **Create the user.** Its key goes to a new file (mode 600), never to the
   terminal:

    ```sh
    labctl s3 user create my-app --display-name "My application" --out my-app.env
    ```

    The file holds `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and
    `AWS_ENDPOINT_URL`, which the `aws` CLI and every SDK read.

2. **Create its bucket**, with a size limit if it should have one:

    ```sh
    labctl s3 bucket create my-bucket --owner my-app --quota 50G
    ```

    The bucket belongs to `my-app` from the start: clusterd creates it with
    that user's own key.

3. **Hand the keys to the app** through its secret handling (a Kubernetes
   Secret through sops in `hgd1-k8s`, or an agenix secret here), then delete
   the file. Never paste them into chat, logs or Git.

## Check it worked

```sh
labctl s3 bucket show my-bucket          # owner my-app, the quota
set -a; . ./my-app.env; set +a           # before deleting the file
aws s3 ls s3://my-bucket                 # empty, no error
```

## Change it later

```sh
labctl s3 bucket quota my-bucket 100G             # or none
labctl s3 user rotate-keys my-app --out new.env   # the old key stops working
labctl s3 bucket delete my-bucket                 # refused while it holds objects
labctl s3 user delete my-app                      # refused while it owns buckets
```

Every change is in `labctl operation list`, with who made it.

## Good to know

- Path-style addressing only; wildcard bucket names aren't configured.
- Bucket names are global within this object store.
- `rotate-keys` removes the old keys right away. To swap without a gap,
  deploy the app with the new file first, then let it pick up the key.
- Without the API: `radosgw-admin user create --uid=my-app --display-name=…`
  on a host, as root, with its output redirected to a root-only file (it
  prints the keys).
