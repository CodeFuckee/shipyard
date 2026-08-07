#!/usr/bin/env bash
#
# glab-ci-retry.sh — 对指定 GitLab CI 作业循环重试,直至成功
#
# 用法:
#   ./glab-ci-retry.sh <job-id> [--max-retries N] [--interval N] [--timeout N]
#
# 示例:
#   ./glab-ci-retry.sh 123456                         # 无限重试直至成功,每 5s 轮询一次
#   ./glab-ci-retry.sh 123456 --max-retries 3 --interval 60 --timeout 3600
#
# 默认: 不传 --max-retries 则不断重试直至成功;不传 --timeout 则没有超时时间;
#       --interval 默认为 5 秒。
#
# 依赖: glab (https://gitlab.com/gitlab-org/cli) + python3 (macOS 自带)
# 说明: 需在目标仓库目录内运行;GitLab 重试会生成新作业 ID,脚本自动跟踪新 ID。
set -uo pipefail

JOB_ID=""
MAX_RETRIES=""     # 最大重试次数,空 = 无限重试直至成功
INTERVAL=5         # 轮询间隔(秒)
TIMEOUT=""         # 总超时(秒),空 = 无超时

usage() {
    echo "用法: $0 <job-id> [--max-retries N] [--interval N] [--timeout N]"
    echo "示例: $0 123456 --max-retries 5 --interval 30 --timeout 7200"
    echo "默认: 不传 --max-retries 则不断重试直至成功;不传 --timeout 则没有超时;--interval 默认为 5 秒"
    exit 1
}

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-retries) MAX_RETRIES="$2"; shift 2 ;;
        --interval)    INTERVAL="$2";    shift 2 ;;
        --timeout)     TIMEOUT="$2";     shift 2 ;;
        -h|--help)     usage ;;
        *)             JOB_ID="$1";      shift ;;
    esac
done

[[ -z "$JOB_ID" ]] && usage

# ---------- 前置检查 ----------
command -v glab >/dev/null 2>&1 || { echo "错误: 未找到 glab,请先安装 https://gitlab.com/gitlab-org/cli"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "错误: 未找到 python3"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "错误: 当前目录不是 git 仓库,请先 cd 到目标仓库目录"; exit 1; }
glab auth status >/dev/null 2>&1 || { echo "错误: glab 未登录,请先执行 'glab auth login'"; exit 1; }

# ---------- 参数校验 ----------
# INTERVAL 必须为正整数
[[ "$INTERVAL" =~ ^[0-9]+$ ]] || { echo "错误: INTERVAL 必须为正整数(当前值: $INTERVAL)"; exit 1; }
# 显式传入 MAX_RETRIES / TIMEOUT 时同样校验
if [[ -n "$MAX_RETRIES" && ! "$MAX_RETRIES" =~ ^[0-9]+$ ]]; then
    echo "错误: MAX_RETRIES 必须为正整数(当前值: $MAX_RETRIES)"; exit 1
fi
if [[ -n "$TIMEOUT" && ! "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "错误: TIMEOUT 必须为正整数(当前值: $TIMEOUT)"; exit 1
fi

# ---------- 工具函数 ----------
# 获取作业状态,失败时输出 __error__
get_status() {
    glab api "projects/:id/jobs/$1" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print("__error__")
    sys.exit(0)
print(data.get("status", "__error__"))
'
}

# 重试作业,成功时输出新作业 ID,失败时输出空
retry_job() {
    glab api --method POST "projects/:id/jobs/$1/retry" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print(data.get("id", ""))
'
}

now_ts() { date +%s; }
now_hm() { date "+%H:%M:%S"; }

# ---------- 主循环 ----------
current_id="$JOB_ID"
retries=0
last_status=""
start_time=$(now_ts)

max_retries_txt="不限"
[[ -n "$MAX_RETRIES" ]] && max_retries_txt="$MAX_RETRIES 次"
timeout_txt="不限"
[[ -n "$TIMEOUT" ]] && timeout_txt="${TIMEOUT}s"
echo "ℹ️  开始监控作业 #$current_id (最大重试 $max_retries_txt,轮询间隔 ${INTERVAL}s,总超时 $timeout_txt)"

while true; do
    if [[ -n "$TIMEOUT" ]]; then
        elapsed=$(( $(now_ts) - start_time ))
        if (( elapsed >= TIMEOUT )); then
            echo "❌ [$(now_hm)] 超过总超时 ${TIMEOUT}s,作业 #$current_id 仍未成功,最终状态: ${last_status:-未知}"
            exit 1
        fi
    fi

    status=$(get_status "$current_id")
    if [[ "$status" == "__error__" ]]; then
        echo "⚠️  [$(now_hm)] 无法获取作业 #$current_id 状态,${INTERVAL}s 后重试..."
        sleep "$INTERVAL"
        continue
    fi

    if [[ "$status" != "$last_status" ]]; then
        echo "ℹ️  [$(now_hm)] 作业 #$current_id 状态: $status (已重试 $retries 次)"
        last_status="$status"
    fi

    case "$status" in
        success)
            elapsed=$(( $(now_ts) - start_time ))
            echo "✅ [$(now_hm)] 作业 #$current_id 成功,耗时 ${elapsed}s"
            exit 0
            ;;
        failed|canceled|skipped)
            # 有限重试模式:次数用尽则退出;无限模式(MAX_RETRIES 为空)则一直重试
            if [[ -n "$MAX_RETRIES" ]] && (( retries >= MAX_RETRIES )); then
                echo "❌ [$(now_hm)] 作业 #$current_id $status,已达最大重试次数 $MAX_RETRIES"
                exit 1
            fi
            retries=$((retries + 1))
            if [[ -n "$MAX_RETRIES" ]]; then
                echo "🔄 [$(now_hm)] 作业 #$current_id $status,开始第 $retries/$MAX_RETRIES 次重试..."
            else
                echo "🔄 [$(now_hm)] 作业 #$current_id $status,开始第 $retries 次重试..."
            fi
            new_id=$(retry_job "$current_id")
            if [[ -z "$new_id" ]]; then
                echo "❌ [$(now_hm)] 重试作业 #$current_id 失败(GitLab API 返回错误)"
                exit 1
            fi
            echo "   ↳ 已触发重试,新作业 ID: #$new_id"
            current_id="$new_id"
            last_status=""
            sleep "$INTERVAL"
            ;;
        running|pending|created|waiting_for_resource|preparing|scheduled)
            sleep "$INTERVAL"
            ;;
        manual)
            echo "❌ [$(now_hm)] 作业 #$current_id 为手动触发(manual),需人工在 GitLab 页面点击运行,脚本无法自动完成"
            exit 1
            ;;
        *)
            echo "⚠️  [$(now_hm)] 未知状态 '$status',${INTERVAL}s 后继续轮询..."
            sleep "$INTERVAL"
            ;;
    esac
done
