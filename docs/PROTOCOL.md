# 剪链传输协议 v1

本文件描述剪链当前实现（协议版本 `1`）的发现、配对、认证、加密和剪贴板消息格式。参考实现位于：

- `lib/core/crypto.dart`
- `lib/network/discovery_service.dart`
- `lib/network/peer_connection.dart`
- `lib/network/peer_link.dart`

## 1. 端口与发现

| 用途 | 协议 | 默认端口 |
| --- | --- | --- |
| 设备发现 | UDP broadcast + multicast | `47821` |
| 点对点同步 | TCP | `47820`（被占用时尝试后续端口） |

组播地址：`239.255.77.66`。

发现包是一个 UTF-8 JSON 对象：

```json
{
  "magic": "cliplink-discovery",
  "v": 1,
  "id": "32 lower-case hex characters",
  "name": "设备显示名",
  "platform": "windows | macos | ios | android",
  "port": 47820,
  "ips": ["192.168.1.8"],
  "ts": 1780000000000
}
```

- 设备每 3 秒广播一次。
- 只接受 `magic`、版本、ID 格式和端口均合法的包；自身 ID 被丢弃。
- 接收方额外使用 UDP 包的源地址作为可用连接地址。
- 10 秒未更新的 presence 被移除。
- 退出时发送带 `"bye": true` 的包。
- 发现包不含任何剪贴板内容、配对码或密钥。

## 2. 帧格式

所有 TCP 数据都使用同一层长度分帧：

```text
uint32 big-endian body_length
uint8  secure_flag          // 0 = 明文握手，1 = 加密应用帧
byte[body_length - 1] body
```

- `secure_flag = 0` 时，body 是 UTF-8 JSON（握手消息）。
- `secure_flag = 1` 时，body 是 AES-256-GCM 的密文加 16 字节认证标签。
- 单帧最大 32 MiB。
- 握手阶段单条 JSON 消息最大 64 KiB。
- 收到认证后的明文帧会被视为协议错误并断开连接。

## 3. 身份与握手 transcript

每台设备持久化一个 128 位随机设备 ID（32 位小写十六进制）和显示名称。

握手双方生成：

- 16 字节随机 nonce；
- 每次连接都重新生成的 X25519 临时密钥对（32 字节公钥）。

transcript 由以下字段做“4 字节大端长度前缀 + 原始字节”的拼接后得到：

```text
"cliplink/1"
uint32 1
mode
client_id
server_id
client_name
server_name
client_nonce
server_nonce
client_ephemeral_public
server_ephemeral_public
```

对 transcript 做 SHA-256 得到 `transcript_hash`。会话 SAS 与所有密钥都绑定到该哈希。

## 4. 密钥派生

设 `shared` 为 X25519 双方共享密钥（32 字节）。

```text
transcript_hash = SHA-256(transcript)

session_material = HKDF-SHA256(
  ikm  = shared,
  salt = transcript_hash,
  info = "cliplink/session/v1",
  len  = 72
)

pairing_secret = HKDF-SHA256(
  ikm  = shared,
  salt = transcript_hash,
  info = "cliplink/pairing/v1",
  len  = 32
)
```

`session_material` 切分：

- `client_to_server_key`：字节 0..31
- `server_to_client_key`：字节 32..63
- `client_to_server_iv_prefix`：字节 64..67
- `server_to_client_iv_prefix`：字节 68..71

两端使用相反的发送/接收密钥，因此不存在双向 nonce/key 重用。

6 位验证码（仅自动发现配对时展示）：

```text
digest = SHA-256("cliplink-sas-v1" || transcript_hash)
sas = big_endian_uint32(digest[0..3]) % 1_000_000，左侧补零到 6 位
```

## 5. 连接模式

`mode` 取值为：

- `pair`：附近设备配对，需要接收方人工确认 6 位 SAS；
- `code`：配对码配对，不需要人工确认弹窗，但必须通过配对码 HMAC 证明；
- `connect`：已配对设备重连。

### 5.1 附近设备配对（pair）

```text
Client                                              Server
  | -- hello(mode=pair, client info, nonce, pub) ----> |
  | <-- helloAck(server info, nonce, pub) ------------- |
  |     双方计算 transcript、SAS，并显示 6 位验证码       |
  |     接收方人工核对 SAS 后允许配对                      |
  | <-- pairAccept ------------------------------------ |
  | -- auth(HMAC(pairing_secret, "client")) ---------> |
  | <-- authOk(HMAC(pairing_secret, "server")) -------- |
  | ==== AES-GCM secure channel established ========== |
```

- 发起方在收到 `helloAck` 后显示 SAS。
- 接收方在收到 `helloAck` 发送完成后的 `IncomingPairingRequest` 中显示同一个 SAS。
- 只有接收方明确允许，服务器才会发送 `pairAccept`。
- 配对成功双方把 `pairing_secret` 作为长期配对密钥保存。

### 5.2 配对码配对（code）

配对码：

- 5 个随机字节编码为 8 个 Crockford Base32 字符（40 bit）；
- 允许大小写、空格、连字符，`I/L → 1`，`O → 0`；
- 显示时格式化为 `XXXX-XXXX`；
- 默认 5 分钟失效，成功使用后立即从服务端清除。

客户端在第一个 hello 中发送：

```text
client_code_proof = HMAC-SHA256(
  key  = normalized_code,
  data = fields(
    "cliplink/code-hello/v1",
    1,
    client_id,
    client_nonce,
    client_public_key
  )
)
```

服务端验证通过后，在 `helloAck` 中返回：

```text
server_code_proof = HMAC-SHA256(
  key  = normalized_code,
  data = fields(
    "cliplink/code-ack/v1",
    1,
    server_id,
    client_code_proof,
    server_nonce,
    server_public_key
  )
)
```

双方随后仍需用 `pairing_secret` 完成 `auth` / `authOk`，然后切换到加密通道。

失败时不会消耗配对码。

### 5.3 已配对重连（connect）

```text
Client                                              Server
  | -- hello(mode=connect, client_id, ...) ----------> |
  | <-- helloAck ------------------------------------- |
  | -- auth(HMAC(stored_secret, "client")) ---------> |
  | <-- authOk(HMAC(stored_secret, "server")) -------- |
  | ==== secure channel ============================== |
```

客户端必须在 `helloAck` 中确认 `server_id` 等于本地记录的已配对设备 ID。
服务端只接受本地存在对应 `peer_id` 记录的连接。

认证证明：

```text
proof = HMAC-SHA256(
  key  = auth_secret,
  data = fields("cliplink/auth/v1", 1, role, transcript_hash)
)
```

`role` 为 `client` 或 `server`；两个方向使用不同的证明。

## 6. 应用帧

认证后每个外层帧的 body 是以下结构的 AES-256-GCM 密文：

```text
uint8  message_type        // 1 = control, 2 = clipboard
uint32 header_length
byte[header_length] header_json
byte[...] payload
```

nonce 为 12 字节：

```text
uint32 iv_prefix || uint64 big-endian counter
```

- 每个方向维护独立的 nonce 前缀和从 0 开始递增的计数器。
- AAD 为固定字符串 `cliplink/frame/v1`。
- 传输的 body 为 `ciphertext || 16-byte GCM tag`。
- 计数器有序，发送队列保证并发发送时计数器与密文顺序一致。

### 6.1 控制消息

```json
{"t":"ping"}
{"t":"pong"}
{"t":"bye"}
```

每 20 秒发送一次 ping；75 秒没有收到合法帧则关闭连接。

### 6.2 剪贴板消息

`message_type = 2`，header 示例：

```json
{
  "id": "32 lower-case hex characters",
  "kind": "text",
  "ts": 1780000000000,
  "originId": "32 hex device id",
  "originName": "发送设备名",
  "sha256": "64 lower-case hex characters",
  "size": 23
}
```

- `kind = text`：payload 是 UTF-8 文本，最大 512 KiB。
- `kind = image`：payload 为 PNG 字节，最大 20 MiB，必须带 PNG 签名。
- `size` 必须等于 payload 长度。
- `sha256 = SHA-256(kind_utf8 || 0x00 || payload)`，接收方重新计算并校验。
- 接收方按 `id` 在 2 分钟窗口内去重。
- 接收方写入系统剪贴板时不会再次广播，避免回环。

## 7. 错误消息

握手阶段错误以明文 JSON 返回：

```json
{"t":"error","code":"code-invalid","message":"配对码错误或已过期"}
```

实现中的主要错误码：

| code | 含义 |
| --- | --- |
| `connect-failed` | TCP 连接失败 |
| `version-mismatch` / `bad-ack` | 协议版本不兼容或握手响应无效 |
| `code-invalid` | 配对码错误、过期或不匹配 |
| `code-proof` | 配对码服务端证明校验失败 |
| `not-paired` | 重连时设备没有配对记录 |
| `pair-declined` / `pair-failed` | 接收方拒绝或未完成配对 |
| `auth-failed` | HMAC 认证失败 |
| `identity-mismatch` | 设备 ID 与预期不符 |
| `clip-too-large` / `bad-clip` | 剪贴板内容过大或完整性校验失败 |

握手失败后连接会被关闭；一方超时会终止尝试。

## 8. 安全边界

- 协议面向互信的局域网环境；已配对设备被完全信任。
- 自动配对依赖用户核对 6 位 SAS；不要盲点“允许配对”。
- 配对码有 40 bit 熵、5 分钟窗口、一次性；攻击者在线尝试仍应被限制在网络可达时间内。
- 本地 `peers.json` 保存长期配对密钥；需要操作系统账户或全盘加密的额外保护。
- 剪贴板内容一旦写入系统剪贴板，可能被系统剪贴板历史、输入法或其他有权应用读取，这不受剪链控制。
- 本协议没有前向保密跨会话保证以外的元数据隐藏或流量填充；发现包会暴露设备名称和局域网地址。
- 没有第三方审计；若用于高敏感场景，请自行进行安全评审。
