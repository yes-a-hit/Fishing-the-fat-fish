class_name ScoreBoard
extends RefCounted

## 一局的分。规则全部收在这一个文件里，UI 只负责把数字弹出来。
##
## 三条设计取舍：
##   1. 失手不扣分 —— 扣分只会让玩家不敢按，而这款游戏的乐趣就在「敢按」。
##      连击断了本身已经是惩罚。
##   2. 连击只放大收益、不改难度 —— 爽感来自数字变大，不该顺带把判定调紧。
##   3. 最高分按「整局」算，只在一局结束时落盘，中途退出不留痕。

## 单次判定底分
const PERFECT_BASE := 100
const GOOD_BASE := 45

## 连击倍率：第 2 次命中起 1.15、1.30 …… 到 2.35 封顶。
## 封顶是为了让「一直完美」和「偶尔断连」的分差可见，但不会滚成天文数字。
const COMBO_STEP := 0.15
const COMBO_CAP := 9

## 上鱼底分。豆包是彩蛋，给得少；克劳德难钓，给得最多。
const FISH_BASE := {"small": 120, "mid": 180, "big": 240, "doubao": 60, "claude": 400}

## 结算尾款
const FULL_CATCH_BONUS := 300   ## 三条主鱼一条不落
const PER_BAIT_BONUS := 40      ## 每剩一碗饵
const CLEAN_RUN_BONUS := 200    ## 一次都没失手

## 难度系数：只乘最终分，不乘单次 —— 玩家看到的每次 +180 在任何难度都一样。
const DIFFICULTY_SCALE := {"easy": 0.8, "normal": 1.0, "hard": 1.3}

const PATH := "user://record.json"

var score: int = 0
var combo: int = 0
var best_combo: int = 0
var hits: int = 0
var perfects: int = 0


func reset() -> void:
	score = 0
	combo = 0
	best_combo = 0
	hits = 0
	perfects = 0


## 当前倍率。连击 0/1 都是 1.0，第 2 次起才涨。
func multiplier() -> float:
	var extra := maxi(combo - 1, 0)
	return 1.0 + float(mini(extra, COMBO_CAP)) * COMBO_STEP


## 一次判定。kind 取 "round"(完美，FightSession 的老名字) / "good" / "miss"。
## "round" 这个名字留着不改：qte_overlay 与自测都在用它，多一次改名就多一处漏。
func hit(kind: String) -> Dictionary:
	if kind == "miss" or kind.is_empty():
		combo = 0
		return {"gain": 0, "combo": 0, "mult": 1.0}

	var base := GOOD_BASE
	if kind == "round" or kind == "perfect":
		base = PERFECT_BASE
		perfects += 1
	combo += 1
	hits += 1
	best_combo = maxi(best_combo, combo)

	var mult := multiplier()
	var gain := int(round(float(base) * mult))
	score += gain
	return {"gain": gain, "combo": combo, "mult": mult}


## 上鱼。同样吃当前连击 —— 一路完美捞上来的，比断过连之后捞上来的贵。
func landed(fish_id: String) -> int:
	var base := int(FISH_BASE.get(fish_id, 100))
	var gain := int(round(float(base) * multiplier()))
	score += gain
	return gain


## 一局结束。把尾款、难度系数、历史最高一起算出来。
## 返回的字典直接塞进 summary，结算页拿去画。
## path 只给自测用：默认路径是真的存档，测试不能往里写。
func finalize(summary: Dictionary, difficulty: String, path: String = PATH) -> Dictionary:
	var bonus := 0
	var caught: Array = summary.get("caught", [])
	if caught.has("small") and caught.has("mid") and caught.has("big"):
		bonus += FULL_CATCH_BONUS
	bonus += maxi(int(summary.get("bait_left", 0)), 0) * PER_BAIT_BONUS
	if int(summary.get("miss", 0)) == 0 and int(summary.get("rounds", 0)) > 0:
		bonus += CLEAN_RUN_BONUS

	var scale := float(DIFFICULTY_SCALE.get(difficulty, 1.0))
	var total := int(round(float(score + bonus) * scale))

	var best := ScoreBoard.load_best(path)
	var prev := int(best.get("score", 0))
	var is_record := total > prev
	if is_record:
		ScoreBoard.save_best({"score": total, "combo": best_combo, "difficulty": difficulty}, path)
		prev = total

	return {
		"score": total,
		"bonus": bonus,
		"scale": scale,
		"best_score": prev,
		"best_combo": best_combo,
		"new_record": is_record,
	}


# ---------- 落盘 ----------
#
# 只存一个数字，所以不做版本号、不做迁移：读坏了就当 0，绝不拦着游戏开局。

static func load_best(path: String = PATH) -> Dictionary:
	var empty := {"score": 0, "combo": 0, "difficulty": ""}
	if not FileAccess.file_exists(path):
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return empty
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_warning("[record] 最高分读不出来，按 0 算")
		return empty

	var data: Dictionary = json.data
	return {
		"score": maxi(int(data.get("score", 0)), 0),
		"combo": maxi(int(data.get("combo", 0)), 0),
		"difficulty": String(data.get("difficulty", "")),
	}


static func save_best(data: Dictionary, path: String = PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[record] 写不进 %s" % path)
		return
	file.store_string(JSON.stringify({
		"_note": "历史最高分。score 是整局总分（已乘难度系数），combo 是那一局的最高连击。",
		"score": maxi(int(data.get("score", 0)), 0),
		"combo": maxi(int(data.get("combo", 0)), 0),
		"difficulty": String(data.get("difficulty", "")),
	}, "\t"))
	file.close()
