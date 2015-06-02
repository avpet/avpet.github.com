---
layout: post
title:  "Перегрузка операторов и инфиксные операторы типов"
date:   2015-05-31 14:30:00
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

Scala сильна своими развитыми возможностями для построения [DSL'ей](http://en.wikipedia.org/wiki/Domain-specific_language). К ним относятся возможность определять операторы и implicit-преобразования.

Как известно, в Scala, каждый оператор является вообще-то методом, просто использование операторов выглядит немного по-другому - похоже на использование встроенных операторов в Java (хотя, по правде говоря, компилятор может оптимизировать вызов и использовать все же оператор на уровне байткода). Если мы пишем:

{% highlight scala %}
3 + 5
{% endhighlight %}

На самом деле вызывается метод, `+` определенный для класса `Int`:

{% highlight scala %}
(3).+(5)
{% endhighlight %}

В первом примере `+` используется как оператор, во втором как метод.

Операторы являются методами, верно и обратное - мы можем записывать вызовы методов как операторы. Например, следующие две строки эквивалентны:

{% highlight scala %}
"Alice" startsWith "A"
"Alice".startsWith("A")
{% endhighlight %}

Существуют 3 вида операторов: **инфиксные**, **префиксные** и **постфиксные**. В Scala можно реализовать все 3, но существуют определенные ограничения, связанные с префиксными и постфиксными операторами.

#### Инфиксные операторы ####

В инфиксной записи, оператор размещается между операндами. У этих операторов может быть более теоретически более двух операндов - но в этом случае  все операнды, кроме первого, нужно будет написать в скобках.
Приведем реальный пример с классом, представляющим собой комплексное число, и для которого переопределены операторы `+` и `-`:

{% highlight scala %}
case class ComplexNum(realPart: Double, imgPart: Double) {

  def +(that: ComplexNum) =
    new ComplexNum(this.realPart + that.realPart, this.imgPart + that.imgPart)

  def -(that: ComplexNum) =
    new ComplexNum(this.realPart - that.realPart, this.imgPart - that.imgPart)

  override def toString = realPart + " + " + imgPart + "i"
}
{% endhighlight %}

Теперь мы можем производить действия над комплексными числами:

{% highlight scala %}
val a = new ComplexNum(4.0, 5.0)
val b = new ComplexNum(2.0, 3.0)

println(a) // 4.0 + 5.0i
println(a + b) // 6.0 + 8.0i
println(a - b) // 2.0 + 2.0i
{% endhighlight %}

#### Префиксные операторы ####

Но что если бы мы хотели определить оператор "не" для нашего типа, т.е. тот, который в Java и Scala записывается как "!".
Такой оператор является унарным префиксным, и мы можем сделать и это, хотя и с некоторыми ограничениями по сравнению с инфиксными операторами вроде `+`.

Таким образом можно переопределить только 4 оператора: `+`, `-`, `!`, и `~`. Для переопределения нужно следовать особому соглашению о именовании, т.е. методы в этом случае называться так: `unary_!` or `unary_~` и т.д. Например, мы можем добавить унарный оператор `~` - пусть он будет возвращать модуль комплексного числа. Напомним, что модулем комплексного числа $$z=x+iy$$ обозначается $$\mid z \mid$$ и определяется выражением $$\mid z\mid = \sqrt{x^2+y^2}$$.

{% highlight scala %}
case class ComplexNum(val realPart: Double, val imgPart: Double) {
    // ...
    def unary_~ = Math.sqrt(real * real + imag * imag)
}
{% endhighlight %}

И тогда:

{% highlight scala %}
var b = new Complex(2.0,3.0)
prinln(~b) //  3.60555
{% endhighlight %}

#### Постфиксные операторы ####

В постфиксной записи оператор идет после операнда, и эти операторы тоже являются унарными. В отличие от префиксных операндов, здесь нету соглашения об именовании методов-операторов. Например, запишем постфиксный инкремент для комплексного числа:

{% highlight scala %}
def ++() =
  new ComplexNum(this.realPart + 1, this.imgPart + 1)
{% endhighlight %}

И тогда:

{% highlight scala %}
var b = new Complex(2.0,3.0)
println(b++) // 3.0 + 4.0i
{% endhighlight %}

#### Проблема именования в JVM ####
Формат файлов класса в JVM  не поддерживает имена из «операторных символов», потому при компиляции генерируются синтетические имена.

Запустим по классу `ComplexNum` джавовскую рефлексию:

{% highlight java %}
import java.lang.reflect.Method;

public class Demo {
    public static void main(String[] args) {
        for (Method m: ComplexNum.class.getDeclaredMethods()) {
            System.out.println(m);
        }
    }
}
{% endhighlight %}

и мы получим в числе прочего (вывод приводится с сокращениями для удобочитаемости)

{% highlight java %}
......
public ComplexNum $plus(ComplexNum)
public ComplexNum $minus(ComplexNum)
public double unary_$tilde()
public ComplexNum $plus$plus()
......
{% endhighlight %}

#### Оператор -> ####

Всем известен инфиксный оператор `->`, позволяющий нам создать пару (`Tuple2`), которую мы можем добавить в `Map`:

{% highlight scala %}
object Demo {
  var map = Map("France" -> "Paris")
  map += "Japan" -> "Tokyo"
}
{% endhighlight %}

Покажем, как все это выглядит после перехода от инфиксной формы вызова методов `->` и `+` к нормальной:

{% highlight scala %}
object Demo {
  var map = Map("France".->("Paris"))
  map = map.+("Japan".->("Tokyo"))
}
{% endhighlight %}

и после поиска подходящего implicit'ного преобразования `String` до какого-то типа с методом '->' (в данном случае `ArrowAssoc` из `Predef.scala`) получают "десахаризированную форму" (как мы знаем, `String` в Scala — это, по сути, `java.lang.String` и у него нет метода '->') следующего вида:

{% highlight scala %}
object Demo {
  var map: Map[String, String] = Map.apply(new ArrowAssoc("France").->("Paris"))
  map = map.+((new ArrowAssoc("Japan").->("Tokyo")))
}
{% endhighlight %}

#### Приоритет операторов в Scala ####

С операторами-методами возникает нюанс в смысле приоритета вызова, который, как известно, должен соблюдаться для операторов. Если бы у нас `+` и `*` были бы просто методами, и компилятор бы никак их не различал, то например, результатом выражения:

{% highlight scala %}
2 + 3 * 4
{% endhighlight %}

было бы 20 вместо 14. Т.е. компилятор все-таки обращает внимание на методы-операторы в случае, если они используются как операторы и их имена начинаются с одного из операторных символов, то компилятор все же будет соблюдать приоритет операторов. В [спецификации Scala написано](http://www.scala-lang.org/files/archive/spec/2.11/06-expressions.html#infix-operations):

> The <em>precedence</em> of an infix operator is determined by the operator's first character. Characters are listed below in increasing order of 
> precedence, with characters on the same line having the same precedence.<br><br>
>(all letters)<br>
>|<br>
>^<br>
>&<br>
>= !<br>
>< ><br>
>:<br>
>+ -<br>
>* / %<br>
>(all other special characters)


Итак, если наш метод начинается с `*`, то он имеет приоритет над методом начинающимся с `+`. Который, в свою очередь, имеет приоритет над любым именем начинающимся с "обычной буквы". 

#### Ассоциативность инфиксных операторов ####

По поводу ассоциативности операторов в той же части [спецификации написано следующее ("6.12.3 Infix Operations")](http://www.scala-lang.org/files/archive/spec/2.11/06-expressions.html#infix-operations), указано, что по умолчанию инфиксные операторы являются лево-ассоциативными, т.е. операция `e1 op e2` интерпретируется `e1.op(e2)`. Но есть еще право-ассоциативные операторы - если `op` есть право-ассоциативный оператор, та же самая операция интерпретируется как `{ val x=e1; e2.op(x) }`. Правоссоциативность достигается добавлением двоеточия `:` в качестве последнего символа имени метода.

Классический пример - метод `::` в трейте `List`

{% highlight scala %}
sealed trait List[+A] {
  def ::[B >: A] (x: B): List[B] =
    new Cons(x, this)
}
{% endhighlight %}

Когда мы записываем список `(1,2,3)`

{% highlight scala %}
1 :: 2 :: 3 :: Nil
{% endhighlight %}

фактически это означает 

{% highlight scala %}
Nil.::(3).::(2).::(1)
{% endhighlight %}

Т.е. `::` можно было бы назвать `prepend`.

#### Инфиксные операторы типов ####

Параметрические типы высших порядков (*higher-kinded types*)  - вообще отдельная тема для обсуждения, но стоит кратко сказать, что это такое. Например, предположим, что у нас есть необходимость использовать общее поведение некоего абстрактного контейнера (назовем его `Container`) для разных параметрических контейнерных типов - `Option`, `List`, но мы не знаем, какой именно это будет тип, и то же время не хотим создавать конкретные реализации для каждого случая. Так вот такая возможность в Scala есть, и она немного похожа на каррирование. Например, обычный параметрический тип имеет "конструктор" вида `List[A]`, т.е. тут только один уровень, и задав `A`, мы получим конкретный тип, а в случае параметрических типов высших порядков  - например, `Container[M[_]]`, мы оставляем вопрос о последнем типе открытым.

{% highlight scala %}
scala> trait Container[M[_]] {
     |   def put[A](x: A): M[A];
     | 
     |   def get[A](m: M[A]): A
     | }
defined trait Container

scala>   val container = new Container[List] {
     |     def put[A](x: A) = List(x);
     | 
     |     def get[A](m: List[A]) = m.head
     |   }
container: Container[List] = $anon$1@8519cb4

scala> container.put("hey")
res0: List[String] = List(hey)

scala> container.put(123)
res1: List[Int] = List(123)
{% endhighlight %}

Если коротко, если говорить о выражениях `List[_]` и `Option[_]`, то `List` и `Option` являются типами высших порядков.

Вернемся к операторам. Итак, синтаксис Scala позволяет нам использовать символы `+` и `*` в именах методов и также предоставляет правила, с помощью которых мы можем менять их порядок выполнения - например, мы можем создать правоассоциативный оператор `++` для класса `Foo`:

{% highlight scala %}
class Foo() { def ++:(n:Int) = println(2*n) }
{% endhighlight %}

и затем вызвать его, передав операнд слева, а сам объект класса `Foo` - справа:

{% highlight scala %}
val foo = new Foo()
123 ++: foo
{% endhighlight %}

Так вот оказывается, нечто подобное можно сделать и с типами. Если мы определим тип высшего порядка с двумя параметрами, затем имя этого типа можно использовать как инфиксный оператор типов. Например, спецификация типа `Tuple2[String,Int]` может быть записана как `String Tuple2 Int`. Следующие две строки делают в общем то одно и тоже, потому что объявляют эквивалентные по сути значения:

{% highlight scala %}
val t1:String Tuple2 Int = ("abc",123)
val t2:Tuple2[String,Int] = ("abc",123)
{% endhighlight %}

Синтаксис в первом объявлении выглядит немножко странно в том месте, где мы используем `Tuple2`. Однако Scala позволяет нам использовать символы операторов для имен типов, как и для имен методов, так что мы можем объявить тип высшего порядка с именем `+` or `*` и использовать его в качестве инфиксного оператора типов. Например, мы можем сделать `+` псевдонимом `Tuple2`, а затем объявить абстрактный список пар вида `("строка","целое число")` следующим образом:

{% highlight scala %}
type +[A,B] = Tuple2[A,B]
val pairlist:List[String + Int] = ???
{% endhighlight %}

В разделе 3.2 на странице 16 статьи ["Towards Equal Rights for Higher-Kinded Types"](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.112.6348&rep=rep1&type=pdf) Одерского сотоварищи, изложено как систему типов Scala можно использовать для представления [нумералов Чёрча](http://en.wikipedia.org/wiki/Church_encoding#Church_numerals), в том числе и с помощью инфиксного оператора типов `+`. Майкл Дюриг (Michael Dürig) реализовал [поддержку натуральных чисел Чёрча](https://michid.wordpress.com/2008/04/18/meta-programming-with-scala-part-i-addition/) с использованием системы типов Scala, причем оператор сложения реализован как тип `+`. И он пошел даже [дальше, реализовав оператор `*`](https://michid.wordpress.com/2008/07/30/meta-programming-with-scala-part-ii-multiplication/). 

Но является ли инфиксный оператор типов полезным на практике, а не только как академическое упражнение по реализации нумералов Черча? 

В принципе, можно сказать, что существует как минимум один случай практического использования нумералов Черча и оператора `+`. Йеспер Норденберг (Jesper Nordenberg) реализовал экспериментальный фреймворк для представления единиц измерения [см. проект `MetaScala`](https://www.assembla.com/wiki/show/metascala), а именно  - [Units.scala](http://trac.assembla.com/metascala/browser/src/metascala/Units.scala), который параметризуется для каждой единицы измерения и использует нумералы Черча для представления типа единиц, полученных в результате умножения или деления единиц. Например, операция умножения единиц `*` класса `Quantity` использует инфиксный оператор типов в нумералах Черча для представления перемноженных единиц. Значение, имеющее тип единицы "метр", будет иметь нумерал Черча в той позиции в параметрах типа `Quantity`, который отвечает за длину. Умножение значения в "метрах" на другое значение в "метрах" использует инфиксный нумерал Черча `+` для сложения двух нумералов Черча, в результате которого получается третий нумерал результирующего типа `Quantity`, который таким образом представляет площадь (длину в квадрате).

{% highlight scala %}
def *[M2 <: MInt, KG2 <: MInt, S2 <: MInt, A2 <: MInt, K2 <: MInt, Mol2 <: MInt, CD2 <: MInt](
    m : Quantity[M2, KG2, S2, A2, K2, Mol2, CD2]) = 
      Quantity[M + M2, KG + KG2, S + S2, A + A2, K + K2, Mol + Mol2, CD + CD2](value * m.value)
{% endhighlight %}


Это означает, [как пишет Йеспер в своем блоге](http://jnordenberg.blogspot.com/2008/09/hlist-in-scala-revisited-or-scala.html), что различные комбинации единиц могут проверятся во время компиляции. 

