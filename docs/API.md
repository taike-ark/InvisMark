# API 参考（v0.1）

参考实现自带一个**零依赖**的 HTTP 服务（`invismark api` / `python -m invismark serve`），
业务逻辑在 [`invismark/service.py`](../invismark/service.py)，换成 FastAPI 时业务层不用改。

```bash
python -m invismark serve --host 127.0.0.1 --port 8000
```

- 传输：明文 HTTP（生产请前置 TLS 反向代理）
- 体积上限：40 MB/请求
- 图片传参支持两种形式：`multipart/form-data`（字段名 `file`）或直接把图片字节当 body（`content-type: image/png`）
- 鉴权：v0.1 未实现（单租户/内网），生产需在网关加 JWT + 限流（说明书 §8）

---

## 通用约定

| 项 | 说明 |
|---|---|
| 返回 | `application/json`（证据包为 `application/zip`） |
| 错误形态 | `{"error": "<code>", "message": "<人话>"}` |
| 错误码 | `bad_request` 400、`not_found` 404、`too_large` 413、`too_small` 422、`undecodable` 400、`quota_exceeded` 429、`internal` 500 |

---

## POST /v1/embed

单图嵌入，返回追溯码与成图（base64）。

```bash
curl -X POST "http://127.0.0.1:8000/v1/embed?user=alice&resource_code=F13241" \
     -H "content-type: image/png" --data-binary @photo.png
```

```json
{
  "asset_id": "as_8f2c1d4e5a6b7c8d",
  "trace_id": "01362B6A7100070037279600000000D9083B2A0000000000",
  "resource_code": "F13241",
  "user_index": 1,
  "image_url": "/v1/assets/as_8f2c1d4e5a6b7c8d",
  "quality": { "psnr": 45.18, "ssim": 0.9982, "base_size": [1792, 2400], "blocks_per_bit": 29 },
  "embedded_at": "2026-11-15T11:20:12+00:00",
  "elapsed_ms": 1826.4,
  "image_base64": "iVBORw0KGgo..."
}
```

查询参数：

| 参数 | 必填 | 说明 |
|---|---|---|
| `user` | 否 | 外部用户 ID，服务端分配 `user_index`（默认 `anonymous`） |
| `resource_code` | 否 | base36 资源码，最多 6 位（默认随机生成） |
| `tenant` | 否 | 租户名（默认 `default`） |

错误：`422 too_small`（长边 < 800 px）、`429 quota_exceeded`（超月配额）、`400 undecodable`。

---

## POST /v1/extract

单图提取，**fail-open**：未检出返回 `found: false` 而不是错误码。

```bash
curl -X POST "http://127.0.0.1:8000/v1/extract" \
     -H "content-type: image/png" --data-binary @suspect.png
```

```json
{
  "found": true,
  "trace_id": "01362B6A7100070037279600000000D9083B2A0000000000",
  "resource_code": "F13241",
  "user_index": 1,
  "user": { "external_id": "alice" },
  "embedded_at": "2026-11-15T11:20:12+00:00",
  "confidence": 0.664,
  "corrected_bytes": 0,
  "ber": 0.0,
  "registered": true,
  "elapsed_ms": 396.2
}
```

未检出：

```json
{ "found": false, "reason": "rs decode failed", "confidence": 0.0, "elapsed_ms": 371.5 }
```

`confidence` 是启发式分（纠错字节数 + 相关余量），**不是**概率；建议对外展示"置信度档位"
（高/中/低）而不是精确数值。

---

## GET /v1/traces/{trace_id}

追溯码详情（48 位十六进制）。未登记返回 `404 not_found`。

```json
{
  "trace_id": "01362B6A7100070037279600000000D9083B2A0000000000",
  "tenant_id": "t_1a2b3c4d5e6f",
  "asset_id": "as_8f2c1d4e5a6b7c8d",
  "resource_code": "F13241",
  "user_index": 1,
  "user": { "external_id": "alice" },
  "embedded_at": "2026-11-15T11:20:12",
  "sha256_orig": "…",
  "sha256_wm": "…",
  "size": { "width": 2400, "height": 1800 },
  "quality": { "psnr": 45.18, "ssim": 0.9982 }
}
```

---

## POST /v1/traces/reserve

桌面端离线模式预分配号段（只登记映射，不落图）。

```json
{ "count": 50, "tenant": "default" }
```

```json
{ "trace_ids": ["0136…", "0136…"] }
```

---

## POST /v1/reports

生成证据包 ZIP（`application/zip`），包内含 `manifest.json`、`chain.jsonl`、`verify.py`。

```json
{ "trace_id": "01362B…", "requester": "case-001" }
```

```bash
curl -X POST http://127.0.0.1:8000/v1/reports -H "content-type: application/json" \
     -d '{"trace_id":"01362B…"}' -o case-001.zip
unzip case-001.zip -d case-001 && python case-001/verify.py   # PASS
```

---

## GET /v1/quota

```json
{ "tenant_id": "t_1a2b…", "month": "2026-11", "used": 137, "limit": 10000, "remaining": 9863 }
```

---

## GET /v1/chain/verify

```json
{ "ok": true, "bad_id": null, "tail": [ { "id": 137, "action": "embed", "this_hash": "…" } ] }
```

---

## GET /healthz ｜ GET /openapi.json

健康检查与最小 OpenAPI 描述（路径级，用于客户端生成脚手架）。

---

## 版本兼容

| 版本 | 变更 |
|---|---|
| 0.1 | 首个版本；`trace_id` 24 字节、`confidence` 启发式、无鉴权 |
