import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * 手动迁移JMComic下载目录中的内容后，即使更新了设置中的下载路径，但数据库中的下载路径并未更新，需要手动更新
 * 
 * 使用dbeaver打开data目录下的download.db（sqlite数据库文件），将需要的数据导出到db.txt文件中，然后使用本程序生成更新语句
 * 1. 将db.txt中的内容复制到本程序中，运行本程序，生成output.sql文件
 * 2. 将output.sql文件中的内容复制到dbeaver中执行，即可完成更新
 */
public class JMComicPathConverter {
    public static void main(String[] args) throws IOException {
        // select bookId,savePath,convertPath from download，将结果保存到db.txt文件中
        String basePath = "P:/图包/jmcomic\\\\commies"; // 替换为你的基础路径，这里需要注意commies前后的路径分隔符都是\
        StringBuilder sb = new StringBuilder();
        try (BufferedReader br = new BufferedReader(new FileReader(Paths.get("./db.txt").toFile()))) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] parts = line.split("\t");
                if (parts.length == 3) {
                    String id = parts[0];
                    String savePath = parts[1];
                    String convertPath = parts[2];
                    savePath = savePath.replaceFirst(".*commies", basePath).replaceAll("'", "''");// 文件名称中可能包含单引号，需要转义
                    convertPath = convertPath.replaceFirst(".*commies", basePath).replaceAll("'", "''");
                    String sql = "update download set savePath='" + savePath + "',convertPath='" + convertPath
                            + "' where bookId=" + id;
                    System.out.println(sql);
                    sb.append(sql).append(";\n");
                } else {
                    System.err.println("Invalid line format: " + line);
                }
            }
        } catch (IOException e) {
            System.err.println("Error reading file: " + e.getMessage());
        }

        // 将sb中的内容写入文件，再在数据库中执行
        Path outputPath = Paths.get("output.sql");
        try (BufferedWriter writer = Files.newBufferedWriter(outputPath)) {
            writer.write(sb.toString());
        } catch (IOException e) {
            System.err.println("Error writing to file: " + e.getMessage());
        }
    }
}
