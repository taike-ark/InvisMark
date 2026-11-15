# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""隐迹 InvisMark — 图片隐形水印（盲水印）参考实现。

本项目是「项目说明书」配套的开源实现：DWT + 分块 DCT + SVD 盲水印，
载荷为 24 字节追溯码，RS(64,24) 纠错，零第三方依赖（仅需 numpy）。

快速上手::

    from invismark import trace
    from invismark.core import pipeline

    tid = trace.TraceCode.new(resource_code="F13241", user_index=7)
    pipeline.embed_file("in.jpg", "out.png", tid, seed=1234)
    result = pipeline.extract_file("out.png", seed=1234)
"""

from ._version import __version__

__all__ = ["__version__"]
