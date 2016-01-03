---
layout: post
title:  "'Ad hoc' полиморфизм. Классы типов"
date:   2016-01-02 14:30:00
categories: scala
image: http://imageshack.com/a/img905/4510/8e7vkO.png
---

<script type="text/javascript" src="http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"></script>

<style>
table, th, td {
    border: 1px solid black;
    border-collapse: collapse;
}
th, td {
    padding: 5px;
    text-align: left;
}
.MathJax_Display {
  text-align: left !important;
}
</style>

Полиморфизм - способность функции обрабатывать данные разных типов. Полиморфический тип - такой тип, операции которого могут применятся к значениям других типов:

Существует несколько видов полиморфизма:

* "Ad hoc" полиморфизм: функция описывает различные реализации в зависимости от указанных типов. "Ad hoc" полиморфизм поддерживается во многих языках, например, путем перегрузки функций.
* Параметрический полиморфизм: реализация не полагается на какие-то конкретные типы, и может быть использована для любых типов. Например, параметрический класс `List[_]` описывает семейство типов - `List[String]`, `List[Int]`, `List[List[Set[Date]]]` и т.д. Параметрический полиморфизм повсеместно в функциональном программировании обычно обозначается просто как «полиморфизм». 
* Наследование ("subtyping"), или "полиморфизм подтипов" - класс описывает семейство типов, которые объединены общим суперклассом. В ООП именно это, как правило, называют просто "полиморфизм". Например, `class Record extends Serializable`.

Классы типов - еще один механизм "ad hoc" полиморфизма. Целью типов классов является следующее - мы хотим, чтобы наша функция поддерживала некоторое семейство типов, при этом мы не хотели бы менять собственно эти типы. Эту проблему, конечно, можно было бы решить с помощью адаптеров - в этом случае мы оборачиваем исходный тип. Но таким образом мы скрываем исходный тип, и к тому же заставляем клиентский код передавать значения типа этого вспомогательного адаптера, а не того типа, который нам нужен. Классы типов позволяют решить эти проблемы. 

В Scala, классы типов организованы на базе типов высшего порядка и implcit'ов. Если в параметрическом полиморфизме, в классе `C[T]` мы определяем метод, он работает одинаково для любых параметров - реализация знает только о некотором типе `T`. В случае же "ad-hoc" полиморфизма, функция имеет разные реализации для разных типов аргументов, например, для `1+2` или `“x”+”y”` у нас нужно быдет предоставить 2 разных реализации. 

Типичные use case'ы, которые могут быть решены с помощью классов типов:

1. Синхронизация файлов и директорий в нескольких файловых системах. Файлы могут быть локальными файлами, директориями, или же ссылками на файл (URL). Директории содержат другие файлы (или директории) (пример из книги "Scala In Depth").
2. Вычисление суммы (среднего значения, и др. агрегатных значений) коллекции элементов. Как сделать общую реализацию, с учетом того, причем диапазон типов должен быть ограничен, поскольку операция имеет смысл только для некоторых типов.

#### Синхронизация файлов

В первом случае, в ООП реализации мы определяем абстрактный интерфейс `FileLike` с необходимыми нам методами.

{% highlight scala %}
trait FileLike {
  def name : String
  def exists : Boolean
  def isDirectory : Boolean
  def children : Seq[FileLike]
  def child(name : String) : FileLike
  def mkdirs() : Unit
  def content : InputStream
  def writeContent(otherContent : InputStream) : Unit
}
{% endhighlight %}

Тогда метод синхронизации бы выглядел приблизительно так:

{% highlight scala %}
  def synchronize(from: FileLike, to: FileLike): Unit = {
    def synchronizeFile(file1: FileLike, file2: FileLike): Unit = {
      file2.writeContent(file1.content)
    }

    def synchronizeDirectory(dir1: FileLike, dir2: FileLike): Unit = {
      def findFile(file: FileLike, directory: FileLike): Option[FileLike] =
        (for {
          file2 <- directory.children if file.name == file2.name
        } yield file2).headOption

      for (file1 <- dir1.children) {
        val file2 = findFile(file1, dir2).getOrElse(dir2.child(file1.name))
        if (file1.isDirectory) {
          file2.mkdirs()
        }
        synchronize(file2, file1)
      }
    }

    if (from.isDirectory) {
      synchronizeDirectory(from, to)
    } else {
      synchronizeFile(from, to)
    }
  }
{% endhighlight %}


Очевидно, что в таком варианте легко перепутать `from` и `to`. Чтобы предотвратить это, можно попробовать выделить типы `F` и `T`, для того чтобы гарантировать правильный порядок, тогда нам придется поменять сигнатуру вызова `synchronize` (а также сигнатуры `synchronizeFile` и `synchronizeDirectory`), добавив параметрический аргумент, ограниченный сверху типом `FileLike`:

{% highlight scala %}
def synchronize[F <: FileLike, T <: FileLike](from: F, to: T): Unit

def synchronizeFile(file1: F, file2: T): Unit

def synchronizeDirectory(dir1: F, dir2: T): Unit
{% endhighlight %}

и сам вызов `synchronize` будет осуществляться следуюшим образом:

{% highlight scala %}
synchronize[F, T](file1, file2)
{% endhighlight %}

Правда, `FileLike.children` ничего не знает о типе `F`, поэтому нам придется поменять и сам интерфейс `FileLike`. 

{% highlight scala %}
trait FileLike[T <: FileLike[T]] {
...
  def children : Seq[T]
  def child(name : String) : T
...
}
{% endhighlight %}

Но один недостаток остается все равно - для каждого нового типа файла нам нужно определить новый наследник `FileLike`. И вот здесь можно было бы использовать классы типов. Вместо `FileLike[T <: FileLike[T]]`, мы можем объявить `FileLike[T]`. Такой трейт позволит нам использовать любой тип `T` как файл безо всякого наследования и называется классом типов. Вся идиома в целом выглядит следующим образом: 

1. класс типов - посредством которого мы получаем доступ к некоторому типу; слово "доступ" здесь имеет ключевой смысл, поскольку трейт не будет наследоваться исходными типами, но будет использоваться для доступа (поэтому его можно назвать accessor'ом), и значения исходного типа будут передаваться в качестве параметра.
2. companion-объект с таким же названием - который содержит дефолтные реализации класса типов для некоторых типов - и которые можно или переопределить, или дополнить при необходимости; 
3. собственно методы, с контекстными привязками (context bounds) в тех местах, где используется данный трейт. 

Новая версия трейта `FileLike` будет выглядеть следующим образом - без ограничения типа, и теперь принимающая значение в качестве параметра:

{% highlight scala %}
trait FileLike[T] {
  def name(file : T) : String
  def isDirectory(file : T) : Boolean
  def children(directory : T) : Seq[T]
  def child(parent : T, name : String) : T
  def mkdirs(file : T) : Unit
  def content(file : T) : InputStream
  def writeContent(file : T, otherContent : InputStream) : Unit
}
{% endhighlight %}

Метод `synchronize` приобретет немного другой вид. Здесь появляются контекстные привязки (context bounds) для `F` и `T`. Как известно, это эквивалентно объявлению implicit-параметров типа `FileLike` для наших типов `F` и `T` - `(implicit from: FileLike[F], to: FileLike[T])`. Далее, с помощью метода `Predef.implicitly` мы получаем параметры типа `FileLike`.  Теперь метод `synchronize` может работать с множеством различных типов. 

{% highlight scala %}
  def synchronize[F: FileLike, T: FileLike](from: F, to: T): Unit = {
    val fromHelper = implicitly[FileLike[F]]
    val toHelper = implicitly[FileLike[T]]

    def synchronizeFile(file1: F, file2: T): Unit = {
      toHelper.writeContent(file2, fromHelper.content(file1))
    }

    def synchronizeDirectory(dir1: F, dir2: T): Unit = {

      def findFile(file: F, directory: T): Option[T] =
        (for {file2 <- toHelper.children(directory)
              if fromHelper.name(file) == toHelper.name(file2)
        } yield file2).headOption

      for (file1 <- fromHelper.children(dir1)) {
        val file2 = findFile(file1, dir2).getOrElse(toHelper.child(dir2, fromHelper.name(file1)))
        if (fromHelper.isDirectory(file1)) {
          toHelper.mkdirs(file2)
        }
        synchronize[T, F](file1, file2)
      }
    }

    if (fromHelper.isDirectory(from)) {
      synchronizeDirectory(from, to)
    } else {
      synchronizeFile(from, to)
    }
  }
{% endhighlight %}

Теперь, если мы решим воспользоваться `synchronize`, например, для объектов типа `java.io.File`, 

Для метода `synchronize` потребуется реализация трейта для `java.io.File`. Обычно дефолтные implicit'ные дефолтные реализации класса типов для некоторого множества типов помещают в companion-объект этого трейта.

{% highlight scala %}
import java.io.File
object FileLike {
  implicit val ioFileLike = new FileLike[File] {
    override def name(file: File) =
      file.getName()
    override def isDirectory(file: File) =
      file.isDirectory()
    override def children(directory: File) =
      directory.listFiles()
    override def child(parent: File, name: String) =
      new java.io.File(parent, name)
    override def mkdirs(file: File) : Unit =
      file.mkdirs()
    override def content(file: File) =
      new FileInputStream(file)
    override def writeContent(file: File, otherContent: InputStream) = {
      val bufferedOutput = new java.io.BufferedOutputStream(new java.io.FileOutputStream(file))
      try {
        val bufferedInput = new java.io.BufferedInputStream(otherContent)
        val buffer = new Array[Byte](512)
        var ready: Int = 0
        ready = bufferedInput.read(buffer)
        while (ready != -1) {
          if (ready > 0) {
            bufferedOutput.write(buffer, 0, ready)
          }
          ready = bufferedInput.read(buffer)
        }
      } finally {
        otherContent.close()
        bufferedOutput.close()
      }
    }
  }
}
{% endhighlight %}

Реализация этого accessor'а для трейта `FileLike` очень проста. Большая часть методов просто делегирует вызовы - за исключением метода `writeContent`. Теперь, если компилятору понадобится implicit'ное значение `FileLike[java.io.File]`, то оно находится в companion-объекте `FileLike`. Поскольку компилятор будет искать implicit'ные значения в companion-объекте в самую последнюю очередь, то мы можем переопределять дефолтную реализацию `Filelike[java.io.File]` с помощью импорта или определения в нужном месте. 

#### Вычисление агрегатных значений для коллекции (сумма, среднее и т.д.)  

Допустим, нам нужно вычислить агрегатные значения (например, среднее) на уже отсортированных коллекциях чисел. Допустим также, что нам доступно только взятие элемента по индексу и метод `reduce`. 

{% highlight scala %}
object Statistics {

  def mean(xs: Vector[Double]): Double = {
    xs.reduce(_ + _) / xs.size
  }
}
{% endhighlight %}

В данном варианте реализация необобщенная, т.е. поддерживает только `Double`, но не, например, `Int`. Перегрузка, чреватая дублированием - явно не самый эффективный вариант. Подходящего общего предка вроде `Number` у `scala.Int` и `scala.Double`, в отличие от `java.lang.Integer` и `java.lang.Double`, нету, соответсвенно, такой вариант не пройдет:

{% highlight scala %}
object Statistics {
  def median(xs: Vector[Number]): Number = ???
  def quartiles(xs: Vector[Number]): (Number, Number, Number) = ???
  def iqr(xs: Vector[Number]): Number = ???
  def mean(xs: Vector[Number]): Number = ???
}
{% endhighlight %}

Но даже если бы это было возможно, мы бы все равно теряли бы информацию о типе.

Можно дать следующее определение классам типов - класс типов `C` определяет некоторое поведение, которое должен поддерживать тип `T` для того, чтобы принаддлежать к классу типов `C`. Связь в виде наследования для типов `T` и `C` не нужна. Для того, чтобы сделать некоторый тип членов класса типов, нам нужно предоставить операции, которые должен поддерживать тип `T`. После этого функции, у которых один или более параметров ограничены типом `C`, могут вызываться с аргументами типа `T`.

Т.е. мы добавляем поведение, при этом не оборачивая исходные типы в специально созданные для этого адаптеры.

Создадим класс типов `NumberLike`.

{% highlight scala %}
object Math {
  trait NumberLike[T] {
    def plus(x: T, y: T): T
    def divide(x: T, y: Int): T
    def minus(x: T, y: T): T
  }
}
{% endhighlight %}

Как и в предыдущем случае, класс типов принимает один или более параметров, и не имеет состояния, т.е. его методы оперируют над параметрами типа `T`. Теперь мы создаем дефолтные реализации - для `Int` и `Double`.

{% highlight scala %}
object Math {
...
 object NumberLike {
    implicit object NumberLikeDouble extends NumberLike[Double] {
      def plus(x: Double, y: Double): Double = x + y
      def divide(x: Double, y: Int): Double = x / y
      def minus(x: Double, y: Double): Double = x - y
    }
    implicit object NumberLikeInt extends NumberLike[Int] {
      def plus(x: Int, y: Int): Int = x + y
      def divide(x: Int, y: Int): Int = x / y
      def minus(x: Int, y: Int): Int = x - y
    }
  }

}
{% endhighlight %}

В данном случае, обе реализации практически идентичны, на самом деле это только здесь - в предыдущем случае, реализации для `File` и `URL` были бы совершенно разными. Теперь собственно вызов:

{% highlight scala %}
object Statistics {
  import Math.NumberLike
  def mean[T](xs: Vector[T])(implicit ev: NumberLike[T]): T =
    ev.divide(xs.reduce(ev.plus(_, _)), xs.size)
}
{% endhighlight %}

Метод принимает параметр типа `T` и аргумент `Vector[T]`.

Идея здесь в том, чтобы ограничить параметр таким образом, чтобы метод принимал только типы определенного класса типов - что реализуется с помощью implicit'ного списка параметров. Т.е. необходимо, чтобы значение типа `NumberLike[T]` было доступно в данном контексте. 

#### Контекстные привязки

Ну и конечно, здесь снова стоит применть контекстные привязки вместо списка implicit'ных параметров.

{% highlight scala %}
object Statistics {
  import Math.NumberLike

  def mean[T: NumberLike](xs: Vector[T]): T = {
    val ev = implicitly[NumberLike[T]]
    implicitly[NumberLike[T]].divide(xs.reduce(ev.plus(_, _)), xs.size)
  }
}
{% endhighlight %}

Контекстная привязка `T : NumberLike` означает, что implicit'ное значение типа `NumberLike[T]` должно быть доступно в текущем контексте, и на самом деле эквивалентна списку implicit'ных параметров типа `NumberLike[T]`. Для того, чтобы получить доступ к implicit'ному значению, нужно воспользоваться методом `Predef.implicitly`. Правда, воспользоваться контекстными привязками можно только если класс типов требует 1 параметр типа.

#### Преимущества type-классов

1. Разделение абстракций - мы модифицируем только специально созданные для этого accessor'ы, и нам не нужно менять уже существующие типы.
2. Возможность композиции - с помощью контекстных привязок мы можем указать и поддеживать несколько типов. Это гибче, чем в случае абстрактного интерфейса, или даже их комбинации.
3. Возможность переопределения - классы типов позволяют переопределять дефолтные accessor'ы путем использования implicit'ов.

Источники:

* [https://en.wikipedia.org/wiki/Polymorphism_(computer_science)](https://en.wikipedia.org/wiki/Polymorphism_(computer_science))
* [https://www.manning.com/books/scala-in-depth](https://www.manning.com/books/scala-in-depth)
* [http://danielwestheide.com/blog/2013/02/06/the-neophytes-guide-to-scala-part-12-type-classes.html](http://danielwestheide.com/blog/2013/02/06/the-neophytes-guide-to-scala-part-12-type-classes.html)
* [https://www.safaribooksonline.com/blog/2013/05/28/scala-type-classes-demystified/](https://www.safaribooksonline.com/blog/2013/05/28/scala-type-classes-demystified/)

