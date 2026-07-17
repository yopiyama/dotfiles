#!/usr/bin/env bash
# GitHub PR のレビュー・レビュースレッド・会話コメントをまとめて取得する。
#
# gh CLI (認証済み) 経由で GraphQL API を叩く。REST と違い reviewThreads の
# isResolved / isOutdated が取れるため、解決済みスレッドの除外までここで完結する。
#
# 使い方:
#   fetch-pr-comments.sh [PR番号 | PR URL] [--repo owner/name]
#                        [--since <review-id | UTC ISO8601>]
#                        [--include-resolved] [--format json|md]
#
# 引数を省略した場合はカレントブランチの PR を gh pr view で解決する。
# --since に review の databaseId を渡すと、その review の submittedAt 以降
# (その review 自身を含む) に絞り込む。日時指定は UTC の ISO8601
# (例: 2026-07-08T05:00:00Z, 2026-07-08) のみ。文字列比較でフィルタするため。
set -euo pipefail

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

PR_ARG="" REPO="" SINCE="" INCLUDE_RESOLVED=false FORMAT=json
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO=$2; shift 2 ;;
    --since) SINCE=$2; shift 2 ;;
    --include-resolved) INCLUDE_RESOLVED=true; shift ;;
    --format) FORMAT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "不明なオプション: $1" >&2; exit 1 ;;
    *) PR_ARG=$1; shift ;;
  esac
done
if [ "$FORMAT" != json ] && [ "$FORMAT" != md ]; then
  echo "--format は json か md: $FORMAT" >&2; exit 1
fi

# --- PR の解決 (番号・URL・引数なしのいずれも gh pr view に任せる) ---
view_args=(pr view --json url,title,number)
[ -n "$PR_ARG" ] && view_args=(pr view "$PR_ARG" --json url,title,number)
[ -n "$REPO" ] && view_args+=(--repo "$REPO")
pr_info=$(gh "${view_args[@]}")
PR_URL=$(jq -r .url <<<"$pr_info")
TITLE=$(jq -r .title <<<"$pr_info")
if [[ $PR_URL =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER=${BASH_REMATCH[1]} NAME=${BASH_REMATCH[2]} NUMBER=${BASH_REMATCH[3]}
else
  echo "PR URL を解釈できません: $PR_URL" >&2; exit 1
fi

# --- GraphQL 取得 (gh の --paginate は $endCursor + pageInfo が必須) ---
REVIEWS_QUERY='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){ pullRequest(number:$number){
    reviews(first:50, after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{ databaseId author{login} state body submittedAt url }
    } } } }'

THREADS_QUERY='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){ pullRequest(number:$number){
    reviewThreads(first:50, after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{ isResolved isOutdated path line
        comments(first:100){ nodes{
          author{login} body createdAt url diffHunk pullRequestReview{databaseId}
        } } }
    } } } }'

ISSUE_COMMENTS_QUERY='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){ pullRequest(number:$number){
    comments(first:100, after:$endCursor){
      pageInfo{hasNextPage endCursor}
      nodes{ author{login} body createdAt url }
    } } } }'

fetch_nodes() {
  # $1: クエリ, $2: pullRequest 直下の connection 名。全ページの nodes を連結して返す
  gh api graphql --paginate \
    -f query="$1" -f owner="$OWNER" -f name="$NAME" -F number="$NUMBER" \
    --jq ".data.repository.pullRequest.$2.nodes" | jq -s 'add // []'
}

reviews=$(fetch_nodes "$REVIEWS_QUERY" reviews)
threads=$(fetch_nodes "$THREADS_QUERY" reviewThreads)
issue_comments=$(fetch_nodes "$ISSUE_COMMENTS_QUERY" comments)

# --- --since の解決 ---
SINCE_TIME=""
if [ -n "$SINCE" ]; then
  if [[ $SINCE =~ ^[0-9]+$ ]]; then
    SINCE_TIME=$(jq -r --argjson id "$SINCE" \
      '[.[] | select(.databaseId == $id)][0].submittedAt // empty' <<<"$reviews")
    if [ -z "$SINCE_TIME" ]; then
      echo "review id $SINCE がこの PR に見つかりません" >&2; exit 1
    fi
  else
    SINCE_TIME=$SINCE
  fi
fi

# --- フィルタと整形 ---
result=$(jq -n \
  --argjson reviews "$reviews" \
  --argjson threads "$threads" \
  --argjson issue_comments "$issue_comments" \
  --arg owner "$OWNER" --arg name "$NAME" --argjson number "$NUMBER" \
  --arg title "$TITLE" --arg url "$PR_URL" \
  --arg since "$SINCE" --arg since_time "$SINCE_TIME" \
  --argjson include_resolved "$INCLUDE_RESOLVED" \
'
def login: .author.login // "(unknown)";
# review コメントの createdAt は下書き記入時刻なので、公開時刻 = 所属 review の
# submittedAt で --since を判定する (所属 review が引けなければ createdAt)
($reviews | map({key: (.databaseId | tostring), value: .submittedAt}) | from_entries) as $review_time |
def published_at: $review_time[.pullRequestReview.databaseId | tostring] // .createdAt;
{
  pr: { repo: "\($owner)/\($name)", number: $number, title: $title, url: $url },
  since: (if $since == "" then null else $since end),
  # 本文空の COMMENTED review はスレッドの入れ物なので除外
  reviews: [ $reviews[]
    | select((.body | gsub("\\s"; "") != "") or .state != "COMMENTED")
    | select($since_time == "" or .submittedAt >= $since_time)
    | { review_id: .databaseId, author: login, state, submitted_at: .submittedAt, body, url } ],
  threads: [ $threads[]
    | select($include_resolved or (.isResolved | not))
    | select($since_time == "" or ([.comments.nodes[] | published_at] | max) >= $since_time)
    | { path, line, resolved: .isResolved, outdated: .isOutdated,
        # スレッド先頭コメントの diff hunk (指摘対象コードの抜粋)
        diff_hunk: (.comments.nodes[0].diffHunk // null),
        comments: [ .comments.nodes[]
          | { author: login, created_at: .createdAt, body, url,
              review_id: .pullRequestReview.databaseId } ] } ],
  issue_comments: [ $issue_comments[]
    | select($since_time == "" or .createdAt >= $since_time)
    | { author: login, created_at: .createdAt, body, url } ]
}')

if [ "$FORMAT" = json ]; then
  printf '%s\n' "$result"
  exit 0
fi

jq -r '
def quote: .body // "" | rtrimstr("\n") | split("\n") | map("  > " + .) | join("\n");
def loc: if .line then "\(.path):\(.line)" else .path end;
def flags: [ (if .resolved then "[resolved]" else empty end),
             (if .outdated then "[outdated]" else empty end) ]
           | if length == 0 then "" else " " + join(" ") end;

[ "# PR #\(.pr.number): \(.pr.title)", .pr.url, "" ]
+ (if (.reviews | length) > 0 then
    ["## Reviews"]
    + [ .reviews[] | "- **\(.state)** @\(.author) (\(.submitted_at)) \(.url)"
        + (if (.body | gsub("\\s"; "")) != "" then "\n" + quote else "" end) ]
    + [""]
  else [] end)
+ (if (.threads | length) > 0 then
    ["## Review threads (\(.threads | length))"]
    + [ .threads[] | "### " + loc + flags + "\n"
        + (if .diff_hunk then "```diff\n\(.diff_hunk)\n```\n" else "" end)
        + ([ .comments[] | "- @\(.author) (\(.created_at)) \(.url)\n" + quote ] | join("\n"))
        + "\n" ]
  else [] end)
+ (if (.issue_comments | length) > 0 then
    ["## Issue comments"]
    + [ .issue_comments[] | "- @\(.author) (\(.created_at)) \(.url)\n" + quote ]
    + [""]
  else [] end)
| join("\n")
' <<<"$result"
