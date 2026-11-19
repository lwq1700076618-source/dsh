# phone-control（手机控制模块）

在电脑上通过命令行 / 聊天控制手机。详细原理见 [`../docs/手机控制模块.md`](../docs/手机控制模块.md)。

## 文件用途

| 路径 | 用途 |
|---|---|
| `pc/phone.mjs` | **电脑端 CLI**。用法 `node phone.mjs <tool> key=value ...`。负责签名、下发指令到 ntfy、订阅回执、打印结果 |
| `pc/phone-ui.mjs` | **电脑端 UI 自动化辅助**。调用手机侧 `uiautomator dump`，解析 XML，按可见文字找到控件坐标，再配合 `tap` 点击 |
| `phone/dsh-agent.sh` | **手机端常驻执行器**。订阅 ntfy、校验 HMAC 签名与时间戳、执行命令、回写回执。含单实例锁 |
| `modules/dsh-phone-agent-v1.0.7.zip` | **KernelSU 模块**。开机以 root 执行 `dsh-agent.sh`，实现免手动启动 |

## 使用前准备

1. 手机：Termux + KernelSU（root），并把 `phone/dsh-agent.sh` 放到手机 `~`
2. 把脚本里的占位符换成自己的值：
   - `T="<YOUR_NTFY_TOPIC>"` → 你的 ntfy topic
   - `KEY="<YOUR_HMAC_KEY>"` → 你的 HMAC 密钥
3. 电脑：在 `pc/` 同级目录放 `topic.txt` 与 `hmac.key`（内容与手机一致，**不要提交到仓库**）

## 示例

```bash
# 设闹钟
node phone.mjs alarm hour=7 minute=20 label="高数 博学楼101"

# 导航到某地
node phone.mjs nav q="青岛大学浮山校区"

# 打开微信
node phone.mjs open pkg=com.tencent.mm

# 点按坐标 / 输入文字
node phone.mjs tap x=540 y=1200
node phone.mjs text text="hello"
```

## 安全

- 手机端**只认签名正确的指令**，密钥不经网络传输
- 指令带时间戳，超过 300 秒拒绝（防重放）
- `shell` 工具等同远程 root，公网 topic 若泄露需立刻换 topic 与密钥
