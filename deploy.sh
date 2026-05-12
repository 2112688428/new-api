#!/bin/bash
# new-api 部署更新脚本
# 分支: origin/release-v20260512

set -e

echo "=========================================="
echo "  new-api 部署更新脚本"
echo "=========================================="

# 配置
PROJECT_DIR="/opt/new-api"
BACKUP_DIR="/tmp/new-api-backup"
BRANCH="origin/release-v20260512"

# 1. 备份
echo "[1/4] 备份数据..."
mkdir -p $BACKUP_DIR
cp -rf $PROJECT_DIR/data $BACKUP_DIR/ 2>/dev/null || true
cp -f $PROJECT_DIR/.env $BACKUP_DIR/ 2>/dev/null || true
echo "✓ 备份完成"

# 2. 更新代码
echo "[2/4] 更新代码..."
cd $PROJECT_DIR
git fetch origin
git checkout $BRANCH
echo "✓ 代码更新完成"

# 3. 启动服务
echo "[3/4] 启动服务..."
docker-compose down
docker-compose up -d --build
echo "✓ 服务启动完成"

# 4. 验证
echo "[4/4] 验证服务..."
sleep 10
docker ps | grep new-api
curl -s http://localhost:3000/v1/models | grep -q "models" && echo "✓ API 测试成功" || echo "✗ API 测试失败"

echo "=========================================="
echo "  部署完成！"
echo "=========================================="