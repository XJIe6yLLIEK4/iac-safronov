export PREFIX=safronov-08
export ZONE=ru-central1-b
export CIDR=10.18.1.0/24
export DISK_SIZE=20

yc vpc network create --name "$PREFIX-net"

yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"

yc compute instance create \
  --name "$PREFIX-web-1" \
  --zone "$ZONE" \
  --platform standard-v3 \
  --cores=2 \
  --core-fraction=20 \
  --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
  --hostname "$PREFIX-web-1" \
  --ssh-key ~/.ssh/id_ed25519.pub \
  --labels created-by=cli

# только имена остановленных машин
yc compute instance list --format json | jq -r '.[] | select(.status != "RUNNING") | .name'

yc compute instance delete "$PREFIX-web-1"
yc compute instance delete "$PREFIX-web-manual"

yc vpc subnet delete "$PREFIX-subnet"
yc vpc network delete "$PREFIX-net"