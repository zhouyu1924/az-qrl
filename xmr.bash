#!/usr/bin/env bash
# create-vms-all-regions-simple-parallel.sh
# 基于 single-vm-test.sh：在所有 Recommended 区域并发创建 Standard_B2s VM，并执行启动脚本
# 无配额检测，失败自动跳过

# ======= 可调参数 ===============================================================
VM_SIZE="Standard_B2s"                        # 2 vCPU / 4 GiB RAM
IMAGE_URN="Canonical:ubuntu-24_04-lts:server:latest"
ADMIN_USER="zhouyu"
ADMIN_PASSWORD="20011123zmyZMY@"              # 建议改用 Key Vault 或 SSH
STARTUP_SCRIPT_URL="https://raw.githubusercontent.com/zhouyu1924/xmr/main/sxmr.bash"
CONCURRENCY=6                                 # 并发线程数 (parallel -j / xargs -P)
TAGS="purpose=mass-deploy-b2s"
# ==============================================================================

# ---------- 登录订阅（已登录可注释） ----------
# az login
# az account set --subscription "<your-subscription-id>"

echo "🔍 获取 Recommended 区域列表..."
REGIONS=$(az account list-locations \
           --query "[?metadata.regionCategory=='Recommended'].name" -o tsv)

# ---------- 函数：创建并配置 VM ----------
create_vm() {
  local LOCATION="$1"
  local RG="rg-$LOCATION"
  local VM="vm-$LOCATION"

  echo "🚀 [$LOCATION] 开始创建 VM..."

  # 1. 资源组
  if ! az group create -n "$RG" -l "$LOCATION" --tags "$TAGS" --output none 2>/dev/null; then
    echo "❌ [$LOCATION] 创建资源组失败，跳过"
    return
  fi

  # 2. 创建 VM（同步等待）
  if ! az vm create \
        --name "$VM" \
        --resource-group "$RG" \
        --location "$LOCATION" \
        --image "$IMAGE_URN" \
        --size "$VM_SIZE" \
        --admin-username "$ADMIN_USER" \
        --authentication-type password \
        --admin-password "$ADMIN_PASSWORD" \
        --public-ip-sku Standard \
        --tags "$TAGS" \
        --only-show-errors \
        --output none; then
    echo "❌ [$LOCATION] VM 创建失败，跳过"
    return
  fi

  # 3. 安装 Custom Script 扩展
  if ! az vm extension set \
        --publisher Microsoft.Azure.Extensions \
        --name customScript \
        --resource-group "$RG" \
        --vm-name "$VM" \
        --settings "{\"fileUris\": [\"$STARTUP_SCRIPT_URL\"], \"commandToExecute\": \"bash sxmr.bash && bash sxmr.bash\"}" \
        --only-show-errors \
        --output none; then
    echo "❌ [$LOCATION] 启动脚本扩展安装失败，跳过"
    return
  fi

  echo "✅ [$LOCATION] 创建完成"
}

export -f create_vm
export VM_SIZE IMAGE_URN ADMIN_USER ADMIN_PASSWORD STARTUP_SCRIPT_URL TAGS

# ---------- 并发执行 ----------
if command -v parallel >/dev/null 2>&1; then
  echo "🔧 使用 GNU parallel 并发 $CONCURRENCY 个任务..."
  echo "$REGIONS" | parallel -j "$CONCURRENCY" --no-notice create_vm {}
else
  echo "🔧 GNU parallel 未安装，使用 xargs -P$CONCURRENCY 并发..."
  echo "$REGIONS" | xargs -n1 -P"$CONCURRENCY" -I{} bash -c 'create_vm "$@"' _ {}
fi

echo "🎉 批量创建提交完毕。可用：az vm list -d --tag $TAGS -o table 查看结果。"

