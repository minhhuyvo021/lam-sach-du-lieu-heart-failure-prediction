# Làm Sạch và Trực Quan Hóa Dữ Liệu Heart Failure Prediction

Pipeline tiền xử lý, kiểm định chất lượng và trực quan hóa dữ liệu lâm sàng (299 hồ sơ bệnh nhân suy tim) triển khai song song trên **SQL Server (Docker)** và **Python**, đảm bảo kết quả đối chiếu trùng khớp tuyệt đối.

## 1. Cấu trúc thư mục
* `docker-compose.yml`: Cấu hình container SQL Server (`sql_doan`) và ánh xạ dữ liệu cục bộ.
* `sql/`: Các kịch bản T-SQL nạp dữ liệu (`00`), khảo sát (`01–02`), điền khuyết phân tầng (`03a–03g`), chuẩn hóa, giảm chiều và xuất dữ liệu (`10_xuat_after.sh`).
* `python/`: Các Jupyter Notebook (`.ipynb`) và kịch bản kiểm chứng (`04_dien_null.py`, `22_xuat_after.py`) đối chiếu chéo từng ô dữ liệu giữa SQL và Python.
* `ket_qua/`: Nhật ký truy vết (audit trail) và bảng tổng hợp qua từng bước xử lý.

## 2. Yêu cầu môi trường (macOS)
* **Docker Desktop** (đã bật Engine).
* **Python 3.12+** kèm môi trường ảo `.venv` đã cài đặt thư viện (`pandas`, `numpy`, `matplotlib`, `seaborn`).

## 3. Hướng dẫn vận hành nhanh

### Khởi động SQL Server và chạy pipeline Python
~~~bash
# 1. Bật container SQL Server
docker compose up -d

# 2. Kích hoạt môi trường ảo Python và chạy kiểm định điền khuyết N01–N07
source .venv/bin/activate
python3 python/04_dien_null.py
~~~

### Xuất dữ liệu sau làm sạch từ SQL và đối chiếu với Python
~~~bash
bash sql/10_xuat_after.sh
python3 python/22_xuat_after.py
~~~

### Dừng container khi kết thúc phiên làm việc
~~~bash
docker compose stop
~~~
