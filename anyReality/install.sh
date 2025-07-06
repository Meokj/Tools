#!/bin/bash
if pgrep singbox > /dev/null; then
  echo "singbox 进程存在，准备杀死..."
  echo
  pkill singbox
  sleep 2
  if pgrep singbox > /dev/null; then
    echo "singbox 进程未退出，强制杀死"
    echo
    pkill -9 singbox
  fi
fi

while true; do
  read -rp "请输入监听端口（1025~65535）: " PORT
  if [[ "$PORT" =~ ^[0-9]{1,5}$ ]] && [ "$PORT" -ge 1025 ] && [ "$PORT" -le 65535 ]; then
    break
  else
    echo "无效端口，请输入 1025~65535 范围内的数字。"
  fi
done

while true; do
  read -r -p "请输入密码: " PASSWORD
  if [[ -z "$PASSWORD" ]]; then
    echo "密码不能为空，请重新输入。"
  elif [[ "$PASSWORD" =~ [[:space:]] ]]; then
    echo "密码不能包含空格，请重新输入。"
  else
    break
  fi
done

cd /usr/local || exit
if [ -d anytls ]; then
  rm -rf anytls
fi

rm -f sing-box-1.12.0-beta.28-linux-amd64.tar.gz
wget https://github.com/SagerNet/sing-box/releases/download/v1.12.0-beta.28/sing-box-1.12.0-beta.28-linux-amd64.tar.gz
tar -xzvf sing-box-1.12.0-beta.28-linux-amd64.tar.gz && \
mv sing-box-1.12.0-beta.28-linux-amd64 anytls
cd anytls || exit
mv sing-box singbox
chmod +x singbox

REALITY_KEYS=$(./singbox generate reality-keypair)
PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep 'Private key' | awk '{print $3}')
PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep 'Public key' | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

cat <<- EOF > config.json
{
    "inbounds": [
        {
            "type": "anytls",
            "listen": "0.0.0.0",
            "listen_port": $PORT,
            "users": [
                {
                    "name": "user",
                    "password": "$PASSWORD"
                }
            ],
            "padding_scheme": [
                "stop=8",
                "0=30-30",
                "1=100-400",
                "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
                "3=9-9,500-1000",
                "4=500-1000",
                "5=500-1000",
                "6=500-1000",
                "7=500-1000"
            ],
            "tls": {
                "enabled": true,
                "server_name": "yahoo.com",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "yahoo.com",
                        "server_port": $PORT
                    },
                    "private_key": "$PRIVATE_KEY",
                    "short_id": "$SHORT_ID"
                }
            }
        }
    ]
}
EOF

echo "配置 systemd 服务..."
cat <<EOF | sudo tee /etc/systemd/system/singbox.service > /dev/null
[Unit]
Description=Sing-box Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/anytls/singbox run
WorkingDirectory=/usr/local/anytls
Restart=on-failure
StandardOutput=append:/var/log/singbox.log
StandardError=append:/var/log/singbox.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable singbox
sudo systemctl restart singbox

sleep 2
if systemctl is-active --quiet singbox; then
  echo "singbox 已通过 systemd 启动成功！"
  echo "日志文件位置：/var/log/singbox.log"
  echo
  echo "-----------------------------------"
  echo "📌 监听端口     : $PORT"
  echo "🔑 密码         : $PASSWORD"
  echo "🔐 Reality 公钥  : $PUBLIC_KEY"
  echo "🔐 Short ID   : $SHORT_ID"
  echo "-----------------------------------"
  echo
else
  echo "singbox 启动失败，请使用 'journalctl -u singbox' 查看详细日志"
  exit 1
fi
