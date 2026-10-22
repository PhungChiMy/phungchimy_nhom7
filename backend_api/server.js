
const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Trang kiểm tra API
app.get('/', (req, res) => {
  res.json({
    success: true,
    group: 'nhom7',
    project: 'Smart Attendance',
    message: 'API Smart Attendance dang hoat dong'
  });
});

// Kiểm tra trạng thái máy chủ
app.get('/api/nhom7/health', (req, res) => {
  res.json({
    success: true,
    group: 'nhom7',
    status: 'online'
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Smart Attendance API dang chay tai cong ${PORT}`);
});
