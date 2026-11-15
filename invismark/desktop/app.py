# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""桌面端（Tkinter 自绘，零第三方依赖）。

功能：单图嵌入 / 单图检测 / 目录批量嵌入 / 导出证据包 / 查看审计链状态。
PySide6 版本（更精致的批量队列）在路线图 M2 里，这里先给「装了 Python 就能用」的版本。

启动：``python -m invismark gui``
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from ..config import Settings
from ..service import Service, ServiceError


def _fmt_quality(q: dict) -> str:
    psnr = q.get("psnr")
    psnr_text = "∞（几乎无损）" if psnr is None else f"{psnr:.2f} dB"
    return f"PSNR {psnr_text} ｜ SSIM {q.get('ssim')} ｜ 每比特 {q.get('blocks_per_bit')} 块"


class DesktopApp:
    def __init__(self, root, settings: Settings | None = None):
        import tkinter as tk
        from tkinter import ttk

        self.tk = tk
        self.root = root
        self.settings = settings or Settings()
        self.service = Service(self.settings)
        root.title("隐迹 InvisMark · 图片隐形水印（本地离线）")
        root.geometry("820x620")
        root.minsize(720, 540)

        style = ttk.Style()
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("Title.TLabel", font=("Microsoft YaHei UI", 16, "bold"))
        style.configure("Hint.TLabel", foreground="#666")
        style.configure("Danger.TLabel", foreground="#c62828")

        header = ttk.Frame(root, padding=(16, 14, 16, 6))
        header.pack(fill="x")
        ttk.Label(header, text="隐迹 InvisMark", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            header,
            text="DWT + 分块 DCT + 扩频 + RS(64,24) ｜ 24 字节追溯码 ｜ 完全离线，不上传图片",
            style="Hint.TLabel",
        ).pack(anchor="w")

        actions = ttk.Frame(root, padding=(16, 8))
        actions.pack(fill="x")
        self.btn_embed = ttk.Button(actions, text="选择图片并嵌入", command=self.embed_one)
        self.btn_embed.pack(side="left", padx=(0, 8))
        self.btn_extract = ttk.Button(actions, text="选择图片并检测", command=self.extract_one)
        self.btn_extract.pack(side="left", padx=(0, 8))
        ttk.Button(actions, text="批量嵌入目录…", command=self.batch).pack(side="left", padx=(0, 8))
        ttk.Button(actions, text="导出证据包…", command=self.export_evidence).pack(side="left")
        ttk.Button(actions, text="校验审计链", command=self.verify_chain).pack(side="left", padx=(8, 0))

        body = ttk.Frame(root, padding=(16, 6))
        body.pack(fill="both", expand=True)
        self.preview = tk.Label(
            body, text="未选择图片", relief="groove", anchor="center", background="#fafafa"
        )
        self.preview.pack(side="left", fill="both", expand=True, padx=(0, 10))
        self._preview_image = None

        log_frame = ttk.Frame(body)
        log_frame.pack(side="right", fill="both", expand=True)
        self.log = tk.Text(log_frame, width=44, wrap="word", state="disabled",
                           font=("Consolas", 10))
        scroll = ttk.Scrollbar(log_frame, command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self.log.pack(side="left", fill="both", expand=True)

        status = ttk.Frame(root, padding=(16, 6, 16, 10))
        status.pack(fill="x")
        self.status = ttk.Label(
            status,
            text=f"数据库：{os.path.abspath(self.settings.db_path)}",
            style="Hint.TLabel",
        )
        self.status.pack(anchor="w")
        root.protocol("WM_DELETE_WINDOW", self.on_close)
        self._last_watermarked: tuple[str, bytes] | None = None
        self.log_append("就绪。所有处理都在本机完成，图片不会离开这台电脑。")

    # ------------------------------------------------------------ 工具

    def log_append(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text.rstrip() + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")
        self.root.update_idletasks()

    def _show_image(self, path: str) -> None:
        try:
            self._preview_image = self.tk.PhotoImage(file=path)
            self.preview.configure(image=self._preview_image, text="")
        except self.tk.TclError:
            self.preview.configure(image="", text=Path(path).name)

    def on_close(self) -> None:
        try:
            self.service.store.close()
        finally:
            self.root.destroy()

    # ------------------------------------------------------------ 动作

    def embed_one(self) -> None:
        from tkinter import filedialog

        src = filedialog.askopenfilename(
            title="选择要嵌入水印的图片",
            filetypes=[("图片", "*.png *.jpg *.jpeg *.webp"), ("全部", "*.*")],
        )
        if not src:
            return
        self._show_image(src)
        user = self.settings.default_tenant
        try:
            data = Path(src).read_bytes()
            outcome = self.service.embed(data, user=user)
        except (ServiceError, OSError) as exc:
            self.log_append(f"[失败] {exc}")
            return
        dst_default = str(Path(src).with_name(Path(src).stem + ".wm.png"))
        dst = filedialog.asksaveasfilename(
            title="保存带水印图片", defaultextension=".png",
            initialfile=Path(dst_default).name, filetypes=[("PNG", "*.png")],
        )
        if not dst:
            self.log_append("已取消保存。")
            return
        Path(dst).write_bytes(outcome.image)
        self._last_watermarked = (dst, outcome.image)
        p = outcome.payload
        self.log_append(
            f"[嵌入成功] {Path(src).name}\ntrace_id: {p['trace_id']}\n"
            f"{_fmt_quality(p['quality'])}\n已保存: {dst}"
        )
        self.status.configure(text=f"最近一次嵌入：{p['trace_id']}")

    def extract_one(self) -> None:
        from tkinter import filedialog

        src = filedialog.askopenfilename(
            title="选择要检测的图片",
            filetypes=[("图片", "*.png *.jpg *.jpeg *.webp"), ("全部", "*.*")],
        )
        if not src:
            return
        self._show_image(src)
        try:
            result = self.service.extract(Path(src).read_bytes(), requester="desktop")
        except (ServiceError, OSError) as exc:
            self.log_append(f"[失败] {exc}")
            return
        if result["found"]:
            self.log_append(
                f"[检出] {Path(src).name}\ntrace_id: {result['trace_id']}\n"
                f"资源码: {result['resource_code']} ｜ 用户索引: {result['user_index']}\n"
                f"置信度: {result['confidence']} ｜ 纠错字节: {result['corrected_bytes']}\n"
                f"嵌入时间: {result['embedded_at']}"
            )
        else:
            self.log_append(f"[未检出] {Path(src).name}\n原因: {result.get('reason')}")

    def batch(self) -> None:
        from tkinter import filedialog

        src_dir = filedialog.askdirectory(title="选择要批量嵌入的目录")
        if not src_dir:
            return
        dst_dir = filedialog.askdirectory(title="选择输出目录")
        if not dst_dir:
            return
        files = sorted(
            p for p in Path(src_dir).iterdir()
            if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
        )
        if not files:
            self.log_append("目录里没有可处理的图片。")
            return
        ok = 0
        for p in files:
            try:
                outcome = self.service.embed(p.read_bytes(), user="batch")
                Path(dst_dir, p.stem + ".wm.png").write_bytes(outcome.image)
                ok += 1
                self.log_append(f"  {p.name} → {outcome.payload['trace_id']}")
            except Exception as exc:  # 单张失败不影响整批
                self.log_append(f"  {p.name} 失败：{exc}")
        self.log_append(f"[批量完成] {ok}/{len(files)} 张成功，输出目录：{dst_dir}")

    def export_evidence(self) -> None:
        from tkinter import filedialog, simpledialog

        trace_id = simpledialog.askstring("导出证据包", "输入 trace_id：")
        if not trace_id:
            return
        trace_id = trace_id.strip().upper()
        try:
            blob = self.service.evidence_zip(
                trace_id,
                watermarked_bytes=self._last_watermarked[1] if self._last_watermarked else None,
                requester="desktop",
            )
        except ServiceError as exc:
            self.log_append(f"[失败] {exc}")
            return
        dst = filedialog.asksaveasfilename(
            title="保存证据包", defaultextension=".zip",
            initialfile=f"{trace_id}.evidence.zip", filetypes=[("ZIP", "*.zip")],
        )
        if not dst:
            return
        Path(dst).write_bytes(blob)
        self.log_append(f"[证据包] {dst}（{len(blob)} 字节，含 verify.py 可独立校验）")

    def verify_chain(self) -> None:
        result = self.service.verify_chain()
        if result["ok"]:
            self.log_append("[审计链] 完整，未被篡改。")
        else:
            self.log_append(f"[审计链] 异常！首个坏记录 id={result['bad_id']}")


def main(argv: list[str] | None = None) -> int:
    try:
        import tkinter as tk
    except Exception as exc:  # pragma: no cover - 取决于 Python 是否带 Tk
        print(f"tkinter 不可用：{exc}", file=sys.stderr)
        print("Windows/macOS 官方 Python 自带 tkinter；Linux 需安装 python3-tk。", file=sys.stderr)
        return 2
    root = tk.Tk()
    DesktopApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
