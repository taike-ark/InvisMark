# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""命令行入口：``python -m invismark <子命令>``。

子命令：
    demo      生成一张示例图并跑一次嵌入/提取闭环
    embed     单图嵌入
    extract   单图提取
    batch     目录批量嵌入
    trace     查询追溯码
    evidence  生成证据包 ZIP
    verify    校验审计哈希链
    serve     启动 HTTP API
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__
from .config import Settings
from .core import image as imageio
from .core import pipeline, trace
from .store import Store


def _settings(args) -> Settings:
    s = Settings()
    if getattr(args, "db", None):
        s.db_path = args.db
    if getattr(args, "data", None):
        s.data_dir = args.data
    if getattr(args, "tenant", None):
        s.default_tenant = args.tenant
    return s


def _print(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False, indent=2, default=str))


# ---------------------------------------------------------------- demo


def _synth(width: int = 1200, height: int = 800):
    import numpy as np

    rng = np.random.default_rng(7)
    x = np.linspace(0, 255, width, dtype=np.float32)[None, :]
    y = np.linspace(0, 255, height, dtype=np.float32)[:, None]
    base = 0.6 * x + 0.4 * y
    img = np.stack([base, base * 0.85 + 30.0, base * 0.7 + 55.0], axis=-1)
    img += rng.normal(0, 14, img.shape)
    return np.clip(img, 0, 255).astype("uint8")


def cmd_demo(args) -> int:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rgb = _synth(args.width, args.height)
    src = out / "demo-source.png"
    wm = out / "demo-watermarked.png"
    imageio.save(src, rgb)
    code = trace.TraceCode.new("F13241", 7)
    res = pipeline.embed_file(str(src), str(wm), code, args.seed)
    got = pipeline.extract_file(str(wm), args.seed)
    _print({
        "source": str(src),
        "watermarked": str(wm),
        "trace_id": code.hex,
        "psnr": round(res.psnr, 2),
        "ssim": round(res.ssim, 4),
        "blocks_per_bit": res.blocks_per_bit,
        "found": got.found,
        "corrected_bytes": got.corrected_bytes,
        "confidence": round(got.confidence, 3),
    })
    return 0 if got.found else 1


# ---------------------------------------------------------------- embed


def cmd_embed(args) -> int:
    settings = _settings(args)
    from .service import Service

    svc = Service(settings)
    if not Path(args.input).exists():
        print(f"input not found: {args.input}", file=sys.stderr)
        return 2
    data = Path(args.input).read_bytes()
    try:
        outcome = svc.embed(
            data,
            tenant=args.tenant,
            user=args.user,
            resource_code=args.resource or "",
            custom_text=args.text or "",
        )
    except Exception as exc:  # ServiceError / ImageIOError
        print(f"embed failed: {exc}", file=sys.stderr)
        return 1
    Path(args.output).write_bytes(outcome.image)
    payload = dict(outcome.payload)
    payload["output"] = args.output
    _print(payload)
    return 0


# ---------------------------------------------------------------- extract


def cmd_extract(args) -> int:
    settings = _settings(args)
    from .service import Service

    svc = Service(settings)
    data = Path(args.input).read_bytes()
    result = svc.extract(data, requester=args.requester)
    _print(result)
    return 0 if result.get("found") else 1


# ---------------------------------------------------------------- batch


def cmd_batch(args) -> int:
    settings = _settings(args)
    src_dir = Path(args.input)
    dst_dir = Path(args.output)
    dst_dir.mkdir(parents=True, exist_ok=True)
    pattern = args.pattern
    files = sorted(p for p in src_dir.glob(pattern) if p.is_file())
    if not files:
        print(f"no files matched {pattern} in {src_dir}", file=sys.stderr)
        return 2
    from .service import Service

    svc = Service(settings)
    results = []
    for p in files:
        try:
            outcome = svc.embed(p.read_bytes(), tenant=args.tenant, user=args.user,
                                resource_code=args.resource or "")
            dst = dst_dir / (p.stem + ".wm.png")
            dst.write_bytes(outcome.image)
            results.append({"src": p.name, "dst": dst.name, "ok": True,
                            "trace_id": outcome.payload["trace_id"],
                            "psnr": outcome.payload["quality"]["psnr"]})
        except Exception as exc:
            results.append({"src": p.name, "ok": False, "error": str(exc)})
    _print({"count": len(results), "ok": sum(1 for r in results if r["ok"]), "results": results})
    return 0 if all(r["ok"] for r in results) else 1


# ---------------------------------------------------------------- trace / evidence / verify


def cmd_trace(args) -> int:
    settings = _settings(args)
    from .service import Service

    _print(Service(settings).trace_info(args.trace_id))
    return 0


def cmd_evidence(args) -> int:
    settings = _settings(args)
    from .service import Service

    svc = Service(settings)
    data = svc.evidence_zip(args.trace_id, requester=args.requester)
    Path(args.output).write_bytes(data)
    _print({"output": args.output, "bytes": len(data), "trace_id": args.trace_id})
    return 0


def cmd_verify(args) -> int:
    settings = _settings(args)
    from .service import Service

    result = Service(settings).verify_chain()
    _print(result)
    return 0 if result["ok"] else 1


# ---------------------------------------------------------------- serve


def cmd_serve(args) -> int:
    settings = _settings(args)
    settings.host = args.host
    settings.port = args.port
    from .api.app import serve

    serve(args.host, args.port, settings)
    return 0


def cmd_gui(args) -> int:
    settings = _settings(args)
    from .desktop.app import main as desktop_main

    return desktop_main()


# ---------------------------------------------------------------- 解析


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="invisMark",
        description="隐迹 InvisMark · 图片盲水印（DWT+DCT+扩频+RS 纠错）参考实现",
        epilog="文档：docs/ ｜ 许可：Apache-2.0",
    )
    p.add_argument("--version", action="version", version=f"invisMark {__version__}")
    sub = p.add_subparsers(dest="command", required=True)

    def common(sp):
        sp.add_argument("--db", help="SQLite 路径（默认 invismark.db）")
        sp.add_argument("--data", help="数据目录（默认 data/）")
        sp.add_argument("--tenant", help="租户名（默认 default）")

    d = sub.add_parser("demo", help="跑一遍完整闭环，生成示例图")
    d.add_argument("--out", default="demo")
    d.add_argument("--width", type=int, default=1200)
    d.add_argument("--height", type=int, default=800)
    d.add_argument("--seed", type=int, default=20260115)
    d.set_defaults(func=cmd_demo)

    e = sub.add_parser("embed", help="单图嵌入")
    e.add_argument("--in", dest="input", required=True)
    e.add_argument("--out", dest="output", required=True)
    e.add_argument("--user", default="anonymous")
    e.add_argument("--resource", default="")
    e.add_argument("--text", default="", help="自定义嵌入文本（≤13 字节 UTF-8，约 4 个汉字）")
    common(e)
    e.set_defaults(func=cmd_embed)

    x = sub.add_parser("extract", help="单图提取")
    x.add_argument("--in", dest="input", required=True)
    x.add_argument("--requester", default="anonymous")
    common(x)
    x.set_defaults(func=cmd_extract)

    b = sub.add_parser("batch", help="目录批量嵌入")
    b.add_argument("--in", dest="input", required=True)
    b.add_argument("--out", dest="output", required=True)
    b.add_argument("--pattern", default="*.png")
    b.add_argument("--user", default="anonymous")
    b.add_argument("--resource", default="")
    common(b)
    b.set_defaults(func=cmd_batch)

    t = sub.add_parser("trace", help="查询追溯码详情")
    t.add_argument("trace_id")
    common(t)
    t.set_defaults(func=cmd_trace)

    ev = sub.add_parser("evidence", help="生成证据包 ZIP")
    ev.add_argument("trace_id")
    ev.add_argument("--out", dest="output", required=True)
    ev.add_argument("--requester", default="")
    common(ev)
    ev.set_defaults(func=cmd_evidence)

    v = sub.add_parser("verify", help="校验审计哈希链")
    common(v)
    v.set_defaults(func=cmd_verify)

    s = sub.add_parser("serve", help="启动 HTTP API")
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=8000)
    common(s)
    s.set_defaults(func=cmd_serve)

    g = sub.add_parser("gui", help="打开桌面端（Tkinter，本地离线）")
    common(g)
    g.set_defaults(func=cmd_gui)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args) or 0)
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

