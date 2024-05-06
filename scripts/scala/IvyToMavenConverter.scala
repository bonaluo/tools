
import org.xml.sax.helpers.DefaultHandler
import org.xml.sax.{Attributes, InputSource, SAXException}

import java.io.StringReader
import javax.xml.parsers.SAXParserFactory
import scala.io.Source


object IvyToMavenConverterWithRoot {

  private def convertIvyToMaven(org: String, name: String, rev: String): String = {
    s"""<dependency>
       |    <groupId>$org</groupId>
       |    <artifactId>$name</artifactId>
       |    <version>$rev</version>
       |</dependency>\n""".stripMargin
  }

  def main(args: Array[String]): Unit = {
    println(args.mkString("(", ";", ")"))
    val resultBuilder = new StringBuilder
    val bufferedSource = Source.fromFile(args(0))
    val str = bufferedSource.getLines().filter(_.nonEmpty).reduce(_ + _)
    bufferedSource.close()

    // 必须要有根元素
    val xmlData = str

    val factory = SAXParserFactory.newInstance
    val saxParser = factory.newSAXParser

    val handler = new DefaultHandler() {
      var isDependency = false
      var org = ""
      var name = ""
      var rev = ""

      @throws[SAXException]
      override def startElement(uri: String, localName: String, qName: String, attributes: Attributes): Unit = {
        if (qName.equalsIgnoreCase("dependency")) {
          isDependency = true
          org = attributes.getValue("org")
          name = attributes.getValue("name")
          rev = attributes.getValue("rev")
          resultBuilder.append(convertIvyToMaven(org, name, rev))
        }
      }
    }

    saxParser.parse(new InputSource(new StringReader(xmlData)), handler)

    println(resultBuilder)
    val printWriter = new java.io.PrintWriter(args(0)+"-maven.xml")
    printWriter.write(resultBuilder.toString)
    printWriter.close()    
  }

}