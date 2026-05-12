# KV Cache Per-Turn Metrics

Script: `S-SOCRATES-BE/scripts/export_kv_cache_turn_metrics.py`

## Muc tieu
- Trich xuat chi so theo tung cau hoi (tung request/task), khac voi file snapshot theo run.
- Ho tro minh chung "cau sau tan dung cache cau truoc" cho bao cao TTTN/LVTN.

## Cach chay
```powershell
python .\S-SOCRATES-BE\scripts\export_kv_cache_turn_metrics.py
```

Script se:
1. Yeu cau nhap duong dan log (`turboquant.stderr.log` hoac `baseline.stderr.log`).
2. Hien cac moc `START ...` co trong log.
3. Cho phep loc theo moc thoi gian (4 dinh dang).
4. Xuat CSV `kv_cache_turn_metrics_YYYYMMDD_HHMMSS.csv`.

## Y nghia cot trong CSV
- `run_start`: moc khoi dong run.
- `task_id`: id request noi bo cua llama-server.
- `slot_id`: slot phuc vu request.
- `slot_selection`: cach server chon slot (`LRU`, `LCP similarity`, ...).
- `sim_best`: do tuong dong LCP (neu co). Cao hon thuong cho thay tan dung context.
- `restored_checkpoint_count`: so lan phuc hoi checkpoint context trong task.
- `prompt_eval_ms`, `prompt_eval_tokens`: thoi gian/tokens xu ly prompt.
- `eval_ms`, `eval_tokens`: thoi gian/tokens sinh cau tra loi.
- `total_ms`, `total_tokens`: tong thoi gian/tokens cua task.
- `request_done`: `1` neu thay dau hieu request ket thuc.

## Cach doc nhanh de so sanh TurboQuant vs Baseline
- `total_ms` trung binh: do tre tong the.
- `prompt_eval_ms` va `prompt_eval_tokens`: kha nang xu ly context dau vao.
- `restored_checkpoint_count` + `slot_selection` + `sim_best`: dau hieu tan dung cache/ngu canh.
- Ket hop voi file KV snapshot (`export_kv_cache_metrics.py`) de co du lieu bo nho.

## Luu y
- Log can giu day du (`slot print_timing`, `slot update_slots`, `done request`).
- Neu log bi cat ngan thi mot so cot co the rong.
