# bootanimation（开机动画模块）

用 KernelSU 模块替换 ColorOS 开机动画（全屏自定义视频）。原理与踩坑见 [`../docs/开机动画模块.md`](../docs/开机动画模块.md)。

## 文件用途

| 路径 | 用途 |
|---|---|
| `bootanimation.zip` | **最终动画包**。内含 `desc.txt` + `part0/` 帧序列，`zip -0`（不压缩）打包 |
| `desc.txt` | **动画描述**。ColorOS 私有格式：`g 宽 高 offsetX offsetY fps` + `p 次数 暂停 目录` |
| `module/module.prop` | **KernelSU 模块信息**。模块 id、名称、版本、描述 |
| `module/post-fs-data.sh` | **挂载脚本**。开机早期后台循环 bind mount，把自定义 zip 挂到系统动画路径，不阻塞开机 |

## 安装

1. 把本目录（含 `module/` 与 `bootanimation.zip`）按 KernelSU 模块结构打包：
   ```
   bootanim-test/
   ├─ module.prop
   ├─ post-fs-data.sh
   └─ bootanimation.zip
   ```
2. KernelSU → 模块 → 从本地安装 zip → 重启

## 验证

```bash
# 手机 root 下看日志
cat /data/local/tmp/bootanim.log
# 期望看到 mounted -> /my_product/media/bootanimation/bootanimation.zip
```

## 注意

- `g` 行的宽高是**动画区域**，不是屏幕分辨率
- 帧必须 `zip -0` 存储打包，压缩会拖慢开机解码
- OTA 后系统分区路径可能变化，脚本里 `T1` / `T2` 两个路径都会尝试
