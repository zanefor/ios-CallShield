# CallShield PIR 服务器 — 部署指南

骚扰座机号前缀匹配 PIR 服务器，配合 iOS Live Caller ID Lookup 扩展使用。

## 核心优势

| 指标 | 数值 |
|------|------|
| 前缀规则数 | 2,136（本地 + E.164） |
| 内存占用 | < 10MB |
| 单次查询延迟 | < 1ms（纯内存匹配） |
| 覆盖号码数 | 112 亿 |
| 覆盖率 | 100%（非偏远骚扰号段） |

## 快速启动

```bash
# 安装依赖
pip install -r requirements.txt

# 启动开发服务器
python3 pir_server.py
# 默认监听 0.0.0.0:8443
```

## API 端点

### `POST /lookup` — 查询号码

```bash
curl -X POST http://localhost:8443/lookup \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "02032445445"}'
```

响应：
```json
{
  "block": true,
  "label": "骚扰座机",
  "prefix": "0203",
  "queryTimeMs": 0.12
}
```

### `POST /batch-lookup` — 批量查询

```bash
curl -X POST http://localhost:8443/batch-lookup \
  -H "Content-Type: application/json" \
  -d '{"phoneNumbers": ["02032445445", "02167636213", "13900139000"]}'
```

### `GET /health` — 健康检查

```bash
curl http://localhost:8443/health
```

### `GET /stats` — 规则统计

```bash
curl http://localhost:8443/stats
```

### `POST /build-pir-database` — 构建 PIR 数据库

生成前缀规则数据，用于转换为 Apple PIR 索引格式。

## 生产部署

### 1. 服务器配置建议

- 规格：2C4G（如阿里云 ecs.c6.large）
- 系统：Ubuntu 22.04
- 磁盘：50G（前缀规则仅 ~56KB）
- 带宽：1Mbps（每次查询 <1KB）
- 费用：~50-80 元/月

### 2. 部署步骤

```bash
# SSH 登录服务器
ssh root@your-ecs-ip

# 安装依赖
apt update && apt install -y python3 python3-pip

# 上传项目
cd /opt && mkdir callshield && cd callshield

# 安装 Python 依赖
pip3 install -r requirements.txt

# 测试启动
python3 pir_server.py
```

### 3. 配置 HTTPS（必须，iOS 要求 HTTPS）

```bash
# Let's Encrypt 免费证书
apt install -y certbot
certbot certonly --standalone -d your-domain.com

# 或使用云服务商免费 SSL 证书
```

### 4. 配置 systemd 服务

```ini
# /etc/systemd/system/callshield-pir.service
[Unit]
Description=CallShield PIR Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/callshield
ExecStart=/usr/local/bin/gunicorn -w 4 -b 0.0.0.0:8443 pir_server:app
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable callshield-pir
systemctl start callshield-pir
```

### 5. App 中配置

在 CallShield App 设置中填入：
- 服务器地址：`https://your-domain.com:8443`
- 认证令牌：（可选，用于验证合法用户）

## 从简化版升级到 PIR 生产版

当前服务器是简化版（明文查询），适用于开发测试。生产环境需升级为 Apple 官方 PIR 协议：

1. 使用 [Apple pir-service-example](https://github.com/apple/pir-service-example)
2. 将前缀规则通过 `/build-pir-database` 导出
3. 转换为 PIR 数据库格式
4. 部署同态加密服务
5. 配置 Oblivious HTTP Relay
6. 配置 Privacy Pass 认证

PIR 生产版确保：
- 服务器不知道查询的具体号码
- 服务器不知道是谁在查询
- 完全符合 Apple 隐私要求

## 费用估算

| 项目 | 费用 |
|------|------|
| ECS 2C4G | ~50-80 元/月 |
| 域名（可选） | ~50 元/年 |
| SSL 证书 | 免费（Let's Encrypt） |
| **合计** | **~50-80 元/月** |
