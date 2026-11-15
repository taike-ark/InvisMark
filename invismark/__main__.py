# 隐迹 InvisMark · SPDX-License-Identifier: Apache-2.0
"""``python -m invismark`` 入口。"""

import sys

from .cli import main

if __name__ == "__main__":
    sys.exit(main())
