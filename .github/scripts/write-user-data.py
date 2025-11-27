#!/usr/bin/env python3
"""
将 User Data 写入文件
从环境变量读取 base64 编码的 User Data 内容，解码后写入指定文件
避免在 GitHub Actions 日志中暴露敏感信息，同时避免转义和解析问题
"""

import sys
import os
import base64


def main():
    """主函数"""
    if len(sys.argv) < 2:
        print("Usage: write-user-data.py <output_file>", file=sys.stderr)
        sys.exit(1)

    output_file = sys.argv[1]

    # 从环境变量读取 base64 编码的 User Data（优先使用环境变量，避免在日志中显示）
    user_data_b64 = os.environ.get("USER_DATA_B64", "")

    # 如果环境变量为空，尝试从标准输入读取（向后兼容）
    if not user_data_b64:
        user_data_b64 = sys.stdin.read().strip()

    if not user_data_b64:
        print("Error: User Data content is empty", file=sys.stderr)
        sys.exit(1)

    # 解码 base64
    try:
        user_data = base64.b64decode(user_data_b64).decode("utf-8")
    except Exception as e:
        print(f"Error: Failed to decode base64 User Data: {e}", file=sys.stderr)
        sys.exit(1)

    # 写入文件
    try:
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(user_data)

        # 输出文件大小（用于验证）
        file_size = len(user_data.encode("utf-8"))
        print(
            f"User Data file created: {output_file} ({file_size} bytes)",
            file=sys.stderr,
        )
    except Exception as e:
        print(
            f"Error: Failed to write User Data to {output_file}: {e}", file=sys.stderr
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
