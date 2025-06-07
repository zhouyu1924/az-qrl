#!/usr/bin/env bash
# create-vms-ubuntu2404-all-regions.sh
# ⚠️ 每个推荐区域都会创建 1 台 VM，务必先确认配额与预算！

# ---------- 可按需修改的参数 ----------
VM_SIZE="Standard_F8as_v6"
IMAGE_URN="Canonical:ubuntu-24_04-lts:server:latest"   # Ubuntu 24.04 LTS
ADMIN_USER="zhouyu"
ADMIN_PASSWORD="20011123zmyZMY@"                       # 明文密码；生产环境请改用安全方案
TAGS="purpose=multi-region-demo"
STARTUP_SCRIPT_URL="https://raw.githubusercontent.com/zhouyu1924/xmr/main/sxmr.bash"

# ---------- 获取所有“推荐”区域 ----------
echo "Fetching Azure regions..."
locations=$(az account list-locations \
  --query "[?metadata.regionCategory=='Recommended'].name" -o tsv)

# ---------- 遍历区域并创建资源 ----------
for location in $locations; do
  rg="rg-$location"
  vm="vm-$location"

  echo -e "\n=== $location ==="

  # 创建资源组
  az group create \
    --name "$rg" \
    --location "$location" \
    --tags "$TAGS" \
    --output none

  # 创建虚拟机（密码登录）
  az vm create \
    --name "$vm" \
    --resource-group "$rg" \
    --location "$location" \
    --image "$IMAGE_URN" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --authentication-type password \
    --admin-password "$ADMIN_PASSWORD" \
    --public-ip-sku Standard \
    --tags "$TAGS" \
    --no-wait

  # 配置启动脚本扩展（Custom Script Extension）
  az vm extension set \
    --publisher Microsoft.Azure.Extensions \
    --name customScript \
    --resource-group "$rg" \
    --vm-name "$vm" \
    --settings "{\"fileUris\": [\"$STARTUP_SCRIPT_URL\"], \"commandToExecute\": \"bash sxmr.bash && bash sxmr.bash\"}" \
    --no-wait
done

echo -e "\n所有创建请求已提交！可用 az vm list -d 查看状态。"
