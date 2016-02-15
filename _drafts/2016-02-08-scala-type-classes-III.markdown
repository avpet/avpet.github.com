---
layout: post
title:  "Классы типов - III: пример использования в сериализации в JSON"
date:   2016-02-15 11:30:00
categories: scala
image: http://imageshack.com/a/img905/4510/8e7vkO.png
---

http://debasishg.blogspot.com/2010/07/sjson-now-offers-type-class-based-json.html
https://github.com/debasishg/sjson/wiki/Examples-of-Type-Class-based-JSON-serialization
http://debasishg.blogspot.com/2010/07/refactoring-into-scala-type-classes.html
https://github.com/spray/spray-json


API для сериализации традиционно строится или с помощью reflection'а (и вспомогательных аннотаций), или с помощью наследования абстрактных интерфейсов, описывающих протокол сериализации. Преимуществом reflection'а является простота использования с точки зрения клиента - хотя с точки зрения внутренней реализации простой ее уже не назовешь.

Также очевидно, что трансформация не всегда происходит "один в один", даже просто из-за того, что есть разница систем типов между JSON и Scala, и из-за type erasure в JVM. Протокол сериализации можно описать с помощью реализации специально созданных для этого абстрактных интерфейсов, но этот вариант застваляет, например, связывать доменные классы с деталями JSON-сериализации. С помощью классов типов же можно вынести артефакты, связанные с сериализацией, в отдельную абстракцию, не связанный непосредственно с основным классом. Таким образом, клиентский код становится чище. Еще одним достоинством классов типов в этом случае является 

Классами типов пользуется на сегодняшний день уже немалое количество библиотек - например, Play JSON базируется на классах типов `Format`, `Reads` и `Writes`. The real advantage of type-classes over more traditional approaches to this problem like reflection is that more issues (like missing conversions, for example) can be detected by the compiler rather than just resulting in errors at runtime. 

Type classes allow you to model orthogonal concerns of an abstraction without hardwiring it within the abstraction itself. This takes the bloat away from the core abstraction implementation into separate independent class structures. Very recently I refactored Akka actor serialization and gained some real insights into the benefits of using type classes. This post is a field report of the same.



Что такое вообще context bound'ы и их предшественники - view bound'ы? Немного предыстории type class'ов.

И тот и другой были попыткой достичь в той или иной степени эффекта type class'ов, которые уже существовали в Haskell. Сперва появились в Scala появились т.н. view (см. [спецификацию Scala, раздел 7.3](http://www.scala-lang.org/files/archive/spec/2.11/07-implicit-parameters-and-views.html#views)) - т.е. implicit'ные преобразования (conversion). На базе implicit'ных параметров и методов можно построить implicit'ные преобразования, или views. Такое преобразование из типа `S` в тип `T` определяется implicit'ным же значением, имеющим тип функции вида `S=>T` или `(=>S)=>T`. 

Implicit'ные преобразования часто полезны, например, в случае, когда мы работаем с двумя библиотеками, которые ничего не знают друг о друге. Каждая из библиотек может по своему моделировать одну и ту же сущность. Implicit'ные преобразования помогают или избавиться, или уменьшить количество явных преобразований одного типа в другой.

Как известно, функция неявного преобразования, или *implicit conversion*, является функция с одним параметром и ключевым словом `implicit`, автоматически преобразующая значения одного типа в значения другого типа. Например, мы хотим сконвертировать целые значения `n` в дробные значения `n / 1`. В таком случае преобразование будет выглядеть вот так:

{% highlight scala %}
implicit def int2Fraction(n: Int) = Fraction(n, 1) 
{% endhighlight %}

И срабатывает вот так: 

{% highlight scala %}
val result = 3 * Fraction(4, 5) // Неявно вызывает int2Fraction(3) 
{% endhighlight %}

Т.е. целое число `3` превращается в объект `Fraction`, который затем умножается на `Fraction(4, 5)`.

Теперь немного отвлечемся на ограничения типов - существуют ситуации, когда нам нужно наложить ограничения на параметрические типы. Например, пусть есть тип `Pair`, в котором оба значения имеют одинаковые типы: 

{% highlight scala %}
class Pair[T](val first: T, val second: T) 
{% endhighlight %}

В этом типе присутствует метод `smaller`, который возвращает меньшее из значений: 

{% highlight scala %}
class Pair[T](val first: T, val second: T) {
  def smaller = if (first.compareTo(second) < 0) first else second
// Error
}
{% endhighlight %}

Что, естественно, не будет работать — поскольку о типе `T` нам неизвестно ничего, в том числе и то, что он имеет метод `compareTo`. Для этого нам нужно добавить *upper bound*, или верхнюю границу типа `T <: Comparable[T]`, с помощью которой мы декларируем, что `T` должен быть подтипом `Comparable[T]`. 

{% highlight scala %}
class Pair[T <: Comparable[T]](val first: T, val second: T) {
  def smaller = if (first.compareTo(second) < 0) first else second
}
{% endhighlight %}

Но этот пример тоже несколько упрощенный и не без недостатков. Если мы попробуем воспользоваться `Pair(4, 2)`, то компилятор скажет, что `T = Int`, и ограничение `T <: Comparable[T]` не выполнено -  `Int` из стандартной библиотеки Scala не является подтипом `Comparable[Int]`, в отличие джавовского `java.lang.Integer`. И существует тип-обертка `RichInt`, который реализует `Comparable[Int]`, вместе с соответствующим implicit преобразованием из `Int` в `RichInt`. Для того, чтобы мы могли задекларировать, что тип `T` может при необходимости быть неявно сконвертирован, используется т.н. *view bound*: 

{% highlight scala %}
class Pair[T <% Comparable[T]] 
{% endhighlight %}

Оператор `<%`  как раз и означает, что `T` может быть сконвертирован в `Comparable[T]` при наличии соответствующего implicit'ного преобразования. *View bound* и был введен в Scala для того чтобы использовать некоторый тип `A` там, где требуется некоторый тип `B`. Обобщенно типичный синтаксис view bound'ов можно изобразить как:

{% highlight scala %}
def f[A <% B](a: A) = a.bMethod
{% endhighlight %}

Другими словами, должны быть доступны implicit'ные преобразования `A` в `B`, для того чтобы мы могли вызывать методы `B` у объекта типа `A`. До Scala 2.8.0 view bound'ы использовались довольно активно, после того как они стали deprecated, их можно найти буквально в нескольких местах в библиотеке.

Но с view bound'ами есть определенные проблемы в смысле гибкости - например, также как и в случае обертки-декоратора, мы теряем информацию об исходном типе, не говоря уже о том, что часто нам нужно создать новый объект. Поэтому следующим шагом на пути реализации type классов стали context bounds - которые появились в Scala 2.8.0.

#### Context Bound

В то время как view bound'ы можно использовать с простыми, непараметрическими типами  (например, `A <% String`), context bound работает только с параметрическими типами, такими как `Ordered[A]`.

Context bound базируется на implicit'ном значении - вместо implicit'ного преобразования, как в случае view bound. Параметр показывает, что для некоторого типа `A`, существует implicit'ное значение (implicit value) типа `B[A]`. Синтаксис метода с context bound'ами выглядит приблизительно так:

{% highlight scala %}
def f[A : B](a: A) = g(a) // g требует implicit'ного значения типа B[A]
{% endhighlight %}

View bound вида `T <% V` требует существования  implicit'ного преобразования conversion из `T` в `V`. Сontext bound же имеет вид `T : M`, где `M` - другой параметрический тип, и требует наличия implicit-ного значения типа `T[M]`. Например, `class Pair[T : Ordering]` требует implicit-ного значения `Ordering[T]`, которое затем может быть использовано внутри метода; тот факт, что нам нужно implicit'ное значение, объявляется с помощью implicit'ного параметра:

{% highlight scala %}
class Pair[T: Ordering](val first: T, val second: T) {
  def smaller(implicit ord: Ordering[T]) = if (ord.compare(first, second) < 0) first else second
}
{% endhighlight %}

Другой пример. Для того, чтобы в Scala, начиная с версии 2.8, создать значение типа `Array[T]`, нам понадобится передать `Manifest[T]` в качестве imlicit'ного параметра. Это необходимо из-за особенностей массивов в JVM (type erasure). Например, если `T`  - это `Int`, то мы хотели бы в конце концов получить массив типа `int[]`. 

{% highlight scala %}
def makePair[T](first: T, second: T)(implicit evidence: Manifest[T]): Array[T] = {
  val r = new Array[T](2); r(0) = first; r(1) = second; r
}
{% endhighlight %}

Или, если мы воспользуемся context bound'ом, то можно записать этот как

{% highlight scala %}
def makePair[T: Manifest](first: T, second: T) = {
  val r = new Array[T](2); r(0) = first; r(1) = second; r
}
{% endhighlight %}

Для вызова `makePair(4, 9)`, компилятор должен найти implicit'ный объект `Manifest[Int]`, т.е. полный вызов выглядит как `makePair(4, 9)(intManifest)`.

Теперь снова ненадолго вернемся к ограничениям типов - чтобы лучше понять, что такое *evidence*. Type constraint'ы дают нам дополнительные возможности для наложения ограничений на типы. Существуют 3 типа ограничений: 

{% highlight scala %}
T =:= U // тип `T` совпадает с `U`
T <:< U // тип `T` является подтипом `U`
T <%< U // для типа `T` должна присутствовать implicit'ная конвертация в тип `U` 
{% endhighlight %}

Для того, чтобы воспользоваться этими ограничениями, мы добавляем implicit'ный параметр - т.н. *"evidence"* (видимо, это означает, что параметр является, так сказать, *свидетелем* типа, т.е. содержит дополнительную информацию о типе): 

{% highlight scala %}
class Pair[T](val first: T, val second: T)(implicit ev: T <:< Comparable[T])
{% endhighlight %}

Кстати, эти type constraint'ы являются частью библиотеки, а не языка. В приведенном примере можно было бы воспользоваться type bound'ом, а именно 

{% highlight scala %}
class `Pair[T <: Comparable[T]]`. 
{% endhighlight %}

Однако, type constraint'ы обладают некоторой дополнительной гибкостью. Например, метод `orNull` в классе `Option`:

{% highlight scala %}
val friends = Map("Fred" -> "Barney", ...) 
val friendOpt = friends.get("Wilma") // An Option[String] 
val friendOrNull = friendOpt.orNull  // A String or null 
{% endhighlight %}

Метод `orNull` будет работать только для типов, которые могут иметь `null` в качестве валидного значения - т.е. мы можем им воспользоваться для типа `String`, но не можем воспользоваться для типа `Int`, но поскольку `orNull` реализует это ограничение как `Null <:< A`, мы все равно можем создать `Option[Int]` - при условии что мы не будем пользоваться методом `orNull` для такого значения. 

Другой случай использования type constraint'ов - для лучшего выведения типов (*type inference*). Например, пусть нам нужно написать функцию, возвращающую первый и последний элемент из некоего `Iterable`:

{% highlight scala %}
def firstLast[A, C <: Iterable[A]](it: C) = (it.head, it.last) 
{% endhighlight %}

Если мы напишем вызов `firstLast(List(1, 2, 3))`, то получим от компилятора сообщение *inferred type arguments `[Nothing,List[Int]]` do not conform to method firstLast's type parameter bounds `[A,C <: Iterable[A]]` don’t conform to `[A, C <: Iterable[A]]`*. Почему `Nothing`? Компонент, занимающийся выведением типов, не может вывести тип `A` из `List(1, 2, 3)` и одновременно с этим `C` за один шаг. Для того, чтобы исправить ситуацию, мы можем сделать так, что сначала будет выведен `C`, а затем `A`: 

{% highlight scala %}
def firstLast[A, C](it: C)(implicit ev: C <:< Iterable[A]) = (it.head, it.last)
{% endhighlight %}

Как уже отмечалось, параметр типа может иметь *context bound* вида `T : M`, где `M` - другой generic тип, и *context bound* требует implicit'ного значения типа `T[M]`. Например, 

{% highlight scala %}
class Pair[T : Ordering] 
{% endhighlight %}

потребует наличия implicit'ного значения типа `Ordering[T]`. И как мы уже знаем, эта запись разворачивается в

{% highlight scala %}
class Pair[T](implicit evidence : Ordering[T])
{% endhighlight %}

Это implicit'ное значение затем может быть использовано в теле функции. Например: 

{% highlight scala %}
class Pair[T: Ordering](val first: T, val second: T) {
  def smaller(implicit ord: Ordering[T]) = if (ord.compare(first, second) < 0) first else second
}
{% endhighlight %}

Если мы напишем `Pair(40, 2)`, то компилятор выведет, что нам нужен тип `Pair[Int]`. Поскольку автоматически нам доступно значение `Ordering[Int]`, объявленное в `scala.math.Ordering`:

{% highlight scala %}
object Ordering extends LowPriorityOrderingImplicits {
... 
  implicit object Int extends IntOrdering
...
}
{% endhighlight %}

то `Int` удовлетворяет нашему context bound'у. При необходимости, мы можем получить evidence с помощью функции `implicitly` из `Predef`: 

{% highlight scala %}
class Pair[T: Ordering](val first: T, val second: T) {
  def smaller = if (implicitly[Ordering[T]].compare(first, second) < 0) first else second
}
{% endhighlight %}

Функция `implicitly` чрезвычайно проста: 

{% highlight scala %}
def implicitly[T](implicit e: T) = e // For summoning implicit values from the nether world 
{% endhighlight %} 

Т.е. создать объект `Pair[T]` можно при наличии соответствующего `Ordering[T]`. Например, если нам нужен `Pair[Point]`, то мы должны создать соответствующие implicit'ное значение типа `Ordering[Point]`: 

{% highlight scala %}
implicit object PointOrdering extends Ordering[Point] {
  def compare(a: Point, b: Point) = ...
}
{% endhighlight %}

#### Использование context bound'ов в стандартной библиотеке

Типичный пример из стандартной библиотеки, не связанный с type class'ами:

{% highlight scala %}
object Array {
//...
  def ofDim[T: ClassManifest](n1: Int): Array[T] =
    new Array[T](n1)
//...
}
{% endhighlight %}

Инициализация массива параметрического типа требует наличия ClassManifest'а, из-за type erasure в JVM с одной стороны, а с другой - того факта, что массивы в Scala ничем не отличаются от других параметрических типов (таких, как например, `List[T]`), и все равно требуют указания типа `T`.

Другой типичный паттерн, который мы уже видели, и встречающийся в стандартной библиотеке:

{% highlight scala %}
def f[A : Ordering](a: A, b: A) = implicitly[Ordering[A]].compare(a, b)
{% endhighlight %}

Здесь, с помощью `implicitly`, мы получаем implicit'ное значение типа `Ordering[A]`.

Ну и как мы уже видели, реализация context bound'ов базируется на implicit'ных параметрах, т.е. context bound'ы являются по сути синтаксическим сахаром, и запись:

{% highlight scala %}
def g[A : B](a: A) = h(a)
{% endhighlight %}

эквивалентна

{% highlight scala %}
def g[A](a: A)(implicit ev: B[A]) = h(a)
{% endhighlight %}

Поэтому, никто не запрещает нам пользоваться "несахаризированным" вариантом записи:

{% highlight scala %}
def f[A](a: A, b: A)(implicit ord: Ordering[A]) = ord.compare(a, b)
{% endhighlight %}

Context bound'ы, как мы уже видели, являются краеугольным камнем для классов типов - паттерн, который является чем-то вроде implicit'ного адаптера.

Примером из библиотеки является использование появившегося в Scala 2.8 `Ordering`. В отличие от `Ordered`, `Ordering` не предполагается для непосредственного наследования, его можно сравнить с компаратором в JDK. 

{% highlight scala %}
def f[A : Ordering](a: A, b: A) = if (implicitly[Ordering[A]].lt(a, b)) a else b
{% endhighlight %}

Хотя, часто можно встретить "несахаризированный" вариант; кстати, имея доступ к `Ordering`, мы можем задействовать implicit'ные для `Ordering` в `scala.math.Ops`, чтобы пользоваться операторами:

{% highlight scala %}
def f[A](a: A, b: A)(implicit ord: Ordering[A]) = {
    import ord._
    if (a < b) a else b
}
{% endhighlight %}

Context bound и типы классов улучшают модульность и уменьшают количество зависимостей между компонентами, и view bound'ы, теоретически, при правильном дизайне, не должны быть востребованы.

Уже имеющиеся view bound'ы часто можно заменить context bound'ами. Приведем несколько синтетический пример. Пусть у нас есть функция с view bound'ом, сигнализирующем о том, что для некоторого типа `T` у нас должно существовать implicit'ное преобразование в `Int`:
	
{% highlight scala %}
scala> def foo[T <% Int](x: T):Int = x
foo: [T](x: T)(implicit evidence$1: T => Int)Int
 
scala> implicit def convertToInt[T](n:T) = n match {
 | case x:String => x.toInt
 | }
warning: there were 1 feature warning(s); re-run with -feature for details
convertToInt: [T](n: T)Int
 
scala> foo("23")
res4: Int = 23
{% endhighlight %}

Естественно, мы получим warning о том, что view bound'ы уже deprecated. Перепишем это с использованием `context bound` - нам также понадобиться implicit'ное значение типа `T => Int`:

{% highlight scala %}
type L[X] = X => Int

implicit def convertToInt[T](n:T): Int = n match {
  case x:String => x.toInt
}

def foo[T : L](x: T):Int = x
{% endhighlight %}

Источники:

* [http://www.horstmann.com/scala/index.html](http://www.horstmann.com/scala/index.html)
* [http://docs.scala-lang.org/tutorials/FAQ/context-and-view-bounds.html](http://docs.scala-lang.org/tutorials/FAQ/context-and-view-bounds.html)
* [http://jatinpuri.com/2014/03/replace-view-bounds/](http://jatinpuri.com/2014/03/replace-view-bounds/)

