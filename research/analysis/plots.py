"""그래프 5종(설계 7-3). 값이 없는 그래프는 만들지 않는다. 평가용(eval) 행이 있으면 그것만, 없으면 예비용으로 그리고 제목에 적는다."""
from __future__ import annotations

import re
import warnings
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib import font_manager  # noqa: E402

from .battery import method_label  # noqa: E402

# 범주 색은 정해 둔 순서로만 쓴다(같은 방법은 그래프마다 같은 색).
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
OTHER = "#8a8a85"   # 8개를 넘는 계열은 새 색을 만들지 않고 '기타' 회색으로 묶는다
INK, MUTED, GRID = "#1f1f1e", "#6b6a64", "#e4e3de"
# 배터리–오차 곡선의 계열(정책 묶음). 같은 계열의 E·주기 변형을 한 선으로 잇는다.
FAMILY_ORDER = ["step_budget[adaptive]", "step_budget[os]", "현재 앱", "fixed", "time_speed", "speed_adaptive",
                "still_suppress[os]", "activity_gated"]
METHOD_ORDER = ["local_straight", "straight", "nearest", "osrm_match", "osrm_match_radius", "hmm_steps", "hmm_nosteps"]
PREFERRED = ["hmm_steps", "osrm_match_radius", "straight", "local_straight"]

# 한글 글꼴: 이 PC에 있는 것만 넣는다(없는 이름을 넣으면 그릴 때마다 경고가 난다).
_KOREAN_FONTS = ["Malgun Gothic", "AppleGothic", "NanumGothic"]


def _korean_fonts() -> list[str]:
    installed = {f.name for f in font_manager.fontManager.ttflist}
    return [f for f in _KOREAN_FONTS if f in installed]


def _font_family() -> list[str]:
    found = _korean_fonts()
    if not found:
        # 글꼴이 없으면 한글이 네모(두부)로 찍힌 그림이 조용히 나오므로 미리 알린다
        warnings.warn("한글 글꼴(Malgun Gothic·AppleGothic·NanumGothic)이 없어 그래프의 한글이 네모로 보일 수 있습니다.",
                      stacklevel=2)
    return found + ["DejaVu Sans"]


plt.rcParams.update({
    "font.family": _font_family(),
    "axes.unicode_minus": False, "axes.edgecolor": MUTED, "axes.labelcolor": INK, "text.color": INK,
    "xtick.color": MUTED, "ytick.color": MUTED, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 120, "savefig.bbox": "tight",
})


def _scope(df: pd.DataFrame) -> tuple[pd.DataFrame, str]:
    if df.empty or "use" not in df:
        return df, ""
    if (df["use"] == "eval").any():
        return df[df["use"] == "eval"], "평가용"
    return df, "예비용"


def _color(i: int) -> str:
    return SERIES[i] if i < len(SERIES) else OTHER


def family(policy: str, detector: str) -> str:
    """현재 앱 방식(hourly·continuous_10m)과 고정 주기 셋은 한 계열로 묶는다."""
    if policy in ("hourly", "continuous_10m"):
        return "현재 앱"
    if policy.startswith("fixed_"):
        return "fixed"
    return method_label(policy, detector)


def main_runs(df: pd.DataFrame) -> pd.DataFrame:
    """곡선에는 본 실험만 넣는다: ttff 0, 파라미터가 없거나 e_m 하나뿐이고 감지기·머문 곳 설정을 바꾸지 않은 재생.
    절제 실험·ttff 민감도는 표(path_metrics.csv)로 본다."""
    def is_main(r) -> bool:
        params = r["params"] if isinstance(r["params"], str) else ""
        if r["ttff"] != 0 or not re.fullmatch(r"(e_m=\S+)?", params):
            return False
        return r["run"] == (method_label(r["policy"], r["detector"]) + (f" {params}" if params else ""))
    return df[df.apply(is_main, axis=1)] if not df.empty else df


def _save(fig, out: Path) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out)
    plt.close(fig)
    return out


def pick_method(df: pd.DataFrame) -> str:
    """곡선에 쓸 복원 방법: 지표가 나온 재생이 가장 많은 방법, 같으면 PREFERRED 순서(제안 → 앱 기본 → 직선)."""
    covered = df.dropna(subset=["p95_m"]).groupby("method")["run"].nunique()
    rank = {m: k for k, m in enumerate(PREFERRED)}
    return sorted(covered.index, key=lambda m: (-covered[m], rank.get(m, len(rank)), m))[0]


def plot_tradeoff(path: pd.DataFrame, out: Path, x: str = "fixes_per_hour", battery: pd.DataFrame | None = None):
    """1. 배터리–오차 곡선: 계열마다 (시간당 측위 횟수 또는 실기기 mAh, 경로 오차 P95)를 x순으로 잇는다.
    복원 방법은 하나만 쓴다(pick_method). y는 시간 단위 측위(hourly)의 수백 m와 나머지 수 m가 함께 보이게 로그 눈금이다."""
    df, scope = _scope(path)
    if df.empty or df["p95_m"].isna().all():
        return None
    method = pick_method(df)
    df = main_runs(df[df["method"] == method])
    g = df.groupby(["run", "policy", "detector"], sort=True).agg(x=(x, "mean"), y=("p95_m", "mean")).reset_index()
    xlabel = "시간당 측위 횟수"
    if battery is not None:
        if battery.empty:
            return None
        g = g.merge(battery.rename(columns={"method": "run"}), on="run")
        g["x"] = g["mah_per_h_mean"]
        xlabel = "시간당 mAh (실기기)"
    g = g.dropna(subset=["x", "y"])
    if g.empty:
        return None
    g["family"] = [family(p, d) for p, d in zip(g["policy"], g["detector"])]
    names = [f for f in FAMILY_ORDER if f in set(g["family"])] + sorted(set(g["family"]) - set(FAMILY_ORDER))
    fig, ax = plt.subplots(figsize=(8, 5))
    for i, name in enumerate(names):
        f = g[g["family"] == name].sort_values("x")
        color = _color(i)
        label = name if i < len(SERIES) else f"기타: {name}"
        # 현재 앱 계열은 서로 다른 두 방식(1시간 주기·연속)이라 선으로 잇지 않는다
        ax.plot(f["x"], f["y"], color=color, linewidth=2, linestyle="none" if name == "현재 앱" else "-", marker="o", markersize=7, markeredgecolor="white",
                markeredgewidth=1.5, label=label, zorder=3)
    ax.set_yscale("log")
    ax.set_xlabel(xlabel)
    ax.set_ylabel("경로 오차 P95 (m, 로그)")
    ax.legend(frameon=False, fontsize=8, loc="upper right")
    ax.set_title(f"수집량–경로 오차 ({method}, {scope} 세션 평균)", loc="left")
    return _save(fig, out)


def plot_battery(summary: pd.DataFrame, out: Path):
    """2. 방식별 시간당 mAh(평균 ± 표준편차, 실기기)."""
    if summary.empty:
        return None
    s = summary.sort_values("mah_per_h_mean")
    fig, ax = plt.subplots(figsize=(8, 0.5 * len(s) + 1.5))
    std = pd.to_numeric(s["mah_per_h_std"], errors="coerce").fillna(0)
    ax.barh(s["method"], s["mah_per_h_mean"], xerr=std, color=SERIES[0], height=0.6,
            error_kw={"ecolor": INK, "elinewidth": 1, "capsize": 3})
    for y, (v, n) in enumerate(zip(s["mah_per_h_mean"], s["n"])):
        ax.annotate(f"{v:.0f} (n={n})", (v, y), textcoords="offset points", xytext=(6, -3), fontsize=8, color=INK)
    ax.set_xlabel("시간당 mAh")
    ax.grid(axis="y", visible=False)
    ax.set_title("방식별 배터리 소모", loc="left")
    return _save(fig, out)


def _bars(ax, labels, values, color):
    ax.barh(labels, values, color=color, height=0.6)
    ax.grid(axis="y", visible=False)


def plot_stay_f1(stays: pd.DataFrame, out: Path):
    """3. 머문 곳 F1(방식·오류 예산별, 세션 평균)."""
    df, scope = _scope(stays)
    if df.empty:
        return None
    df = main_runs(df)   # 그래프 1과 같이 본 실험만(절제·ttff 재생은 표로 본다)
    if df.empty or df["stay_f1"].isna().all():
        return None
    g = df.groupby("run")["stay_f1"].mean().dropna().sort_values()
    fig, ax = plt.subplots(figsize=(8, 0.4 * len(g) + 1.5))
    _bars(ax, g.index, g.values, SERIES[2])
    ax.set_xlim(0, 1)
    ax.set_xlabel("머문 곳 F1")
    ax.set_title(f"머문 곳 검출 ({scope} 세션 평균)", loc="left")
    return _save(fig, out)


def plot_steps(steps: pd.DataFrame, out: Path):
    """4. 걸음 감지 방법별 오차와 탈것 구간 가짜 걸음 수(두 값은 단위가 달라 그래프를 나눈다)."""
    df, scope = _scope(steps)
    if df.empty:
        return None
    panels = [(c, t) for c, t in [("count_abs_error_pct", "걸음 수 오차 |%|"), ("vehicle_false_steps", "탈것 구간 가짜 걸음")]
              if c in df and df[c].notna().any()]
    if not panels:
        return None
    fig, axes = plt.subplots(1, len(panels), figsize=(5 * len(panels), 3.5), squeeze=False)
    for ax, (col, title) in zip(axes[0], panels):
        g = df.groupby("detector")[col].mean().dropna()
        _bars(ax, g.index, g.values, SERIES[1])
        ax.set_title(title, loc="left")
    fig.suptitle(f"걸음 감지 방법 비교 ({scope} 세션 평균)", x=0.01, ha="left")
    return _save(fig, out)


def plot_reconstruct(path: pd.DataFrame, out: Path):
    """5. 복원 방법별 경로 오차 P95(같은 입력). 본 실험 재생 중 모든 방법이 돈 재생만 골라, 방법마다 그 재생들의
    P95 중앙값을 막대로 그린다(시간 단위 측위의 수백 m가 평균을 끌지 않게 중앙값). 방법이 하나뿐이면 그리지 않는다."""
    df, scope = _scope(path)
    if df.empty or df["p95_m"].isna().all():
        return None
    g = main_runs(df).groupby(["run", "method"])["p95_m"].mean().unstack("method")
    if g.shape[1] < 2:
        return None
    g = g.dropna()
    if g.empty:
        return None
    order = [m for m in METHOD_ORDER if m in g.columns] + sorted(m for m in g.columns if m not in METHOD_ORDER)
    med = g[order].median()
    fig, ax = plt.subplots(figsize=(8, 0.45 * len(order) + 1.5))
    ax.barh(order[::-1], med[order[::-1]].values, color=SERIES[0], height=0.6)
    for y, v in enumerate(med[order[::-1]].values):
        ax.annotate(f"{v:.1f}", (v, y), textcoords="offset points", xytext=(6, -3), fontsize=8, color=INK)
    ax.grid(axis="y", visible=False)
    ax.set_xlabel("경로 오차 P95 중앙값 (m)")
    ax.set_title(f"복원 방법별 경로 오차 (같은 재생 {len(g)}개, {scope} 세션)", loc="left")
    return _save(fig, out)


def make_all(tables: dict[str, pd.DataFrame], fig_dir: Path) -> list[Path]:
    made = [
        plot_tradeoff(tables["path_metrics"], fig_dir / "1_tradeoff_fixes.png"),
        plot_tradeoff(tables["path_metrics"], fig_dir / "1_tradeoff_mah.png", battery=tables["battery_summary"]),
        plot_battery(tables["battery_summary"], fig_dir / "2_battery.png"),
        plot_stay_f1(tables["stay_metrics"], fig_dir / "3_stay_f1.png"),
        plot_steps(tables["step_metrics"], fig_dir / "4_steps.png"),
        plot_reconstruct(tables["path_metrics"], fig_dir / "5_reconstruct.png"),
    ]
    return [p for p in made if p is not None]
