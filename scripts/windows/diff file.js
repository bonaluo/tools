const fs = require('fs');

try {
    // 读取文件内容
    const data = fs.readFileSync('E:\\note\\tools\\temp\\temp.txt', 'utf-8');
    // 按换行符拆分内容
    const lines = data.split(/\r?\n/);
    // 输出每一行
    for (const line of lines) {
        if (!fs.existsSync("F:\\video\\owner\\20240630\\" + line)) {
            console.log(line);
        }
    }
} catch (error) {
    console.error('读取文件出错：', error.message);
}
