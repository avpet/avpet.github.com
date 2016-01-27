---
layout: post
title:  "'Ad hoc' полиморфизм. Классы типов - II"
date:   2016-01-21 09:30:00
categories: scala
image: http://imageshack.com/a/img905/4510/8e7vkO.png
---

Источники:

* [https://en.wikipedia.org/wiki/Polymorphism_(computer_science)](https://en.wikipedia.org/wiki/Polymorphism_(computer_science))

Что такое вообще context bound'ы и их предшественники - view bound'ы? Немного предыстории type class'ов.

И тот и другой были попыткой достичь в той или иной степени эффекта type class'ов, которые уже существовали в Haskell. Сперва появились в Scala появились т.н. view (см. [спецификацию Scala, раздел 7.3](http://www.scala-lang.org/files/archive/spec/2.11/07-implicit-parameters-and-views.html#views)) - т.е. implicit'ные преобразования (conversion). На базе imlicit'ных параметров и методов можно построить implicit'ные преобразования, или views. Такое преобразование из типа `S` в тип `T` определяется implicit'ным же значением, имеющим тип функции вида `S=>T` или `(=>S)=>T`. 

Implicit'ные преобразования часто полезны, например, в случае, когда мы работаем с двумя библиотеками, которые ничего не знают друг о друге. Каждая из библиотек может по своему моделировать одну и ту же сущность. Implicit conversion'ы помогают или избавиться, или уменшить количество явных преобразований одного типа в другой.

Как известно, функция неявного преобразования, или *implicit conversion*, является функция с одним параметром и ключевым словом `implicit`, автоматически преобразующая значения одного типа в значения другого типа. Например, мы хотим сконвертировать целые значения `n` в дробные значения `n / 1`. В таком случае преобразование будет выглядеть вот так:

{% highlight scala %}
implicit def int2Fraction(n: Int) = Fraction(n, 1) 
{% endhighlight %}

И срабатывает вот так: 

{% highlight scala %}
val result = 3 * Fraction(4, 5) // Calls int2Fraction(3) 
{% endhighlight %}

Т.е. целое число `3` превращается в объект `Fraction`, который затем умножается на `Fraction(4, 5)`.

Теперь немного отвлечемся на ограничение типов - существуют ситуации, когда нам нужно наложить ограничения на параметрические типы. Например, пусть есть тип `Pair` в котором оба значения имеют одинаковые типы: 

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

Но этот пример тоже несколько упрощенный и не без недостатков. Если мы попробуем воспользоваться `Pair(4, 2)`, то компилятор скажет, что `T = Int`, и ограничение `T <: Comparable[T]` не выполнено -  `Int` из стандартной библиотеки Scala не является подтипом `Comparable[Int]`, в отличие джавовского `java.lang.Integer`. И существует тип-обертка `RichInt`, который реализует `Comparable[Int]`, вместе с соответсвующим implicit преобразованием из `Int` в `RichInt`. Для того, чтобы мы могли задекларировать, что тип `T` может при необходимости быть неявно сконвертирован, используется т.н. *view bound*: 

{% highlight scala %}
class Pair[T <% Comparable[T]] 
{% endhighlight %}

Оператор `<%`  как раз и означает, что `T` может быть сконвертирован в `Comparable[T]` при наличии соотвествующего implicit conversion. *View bound* и был введен в Scala для того чтобы использовать некоторый тип `A` там, где требуется некоторый тип `B`. The typical syntax is this:

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

Для того, чтобы создать значение типа `Array[T]`, нам понадобится `Manifest[T]`. это необходимо из-за особенностей массивов в JVM (type erasure). Например, если `T`  - это `Int`, то мы хотели бы в конце концов получить массив типа `int[]`. 

{% highlight scala %}
def makePair[T: Manifest](first: T, second: T) = {
  val r = new Array[T](2); r(0) = first; r(1) = second; r
}
{% endhighlight %}

Для вызова `makePair(4, 9)`, компилятор должен найти implicit'ный объект `Manifest[Int]`, т.е. полный вызов выглядит как `makePair(4, 9)(intManifest)`.

Type constraints дают нам дополнительные возможности для наложения ограничений на типы. Существуют 3 типа ограничений: 

{% highlight scala %}
T =:= U // тип `T` совпадает с `U`
T <:< U // тип `T` является подтипом `U`
T <%< U // для типа `T` должна присутствовать imlicit'ная конвертация в тип `U` 
{% endhighlight %}

To use such a constraint, you add an “implicit evidence parameter” like this: 

{% highlight scala %}
class Pair[T](val first: T, val second: T)(implicit ev: T <:< Comparable[T])
{% endhighlight %}

These constraints are not built into the language. They are a feature of the Scala library.

In the example above, there is no advantage to using a type constraint over a type bound class `Pair[T <: Comparable[T]]`. However, type constraints are useful in some specialized circumstances. In this section, you will see two uses of type constraints. Type constraints let you supply a method in a generic class that can be used only under certain conditions. Here is an example: 

{% highlight scala %}
class Pair[T](val first: T, val second: T) {
  def smaller(implicit ev: T <:< Ordered[T]) = if (first < second) first else second
}
{% endhighlight %}

You can form a `Pair[File]`, even though `File` is not ordered. You will get an error only if you invoke the `smaller` method. Another example is the `orNull` method in the `Option` class: 

{% highlight scala %}
val friends = Map("Fred" -> "Barney", ...) 
val friendOpt = friends.get("Wilma") // An Option[String] 
val friendOrNull = friendOpt.orNull  // A String or null 
{% endhighlight %}

The `orNull` method can be useful when working with Java code where it is common to encode missing values as `null`. But it can’t be applied to value types such as `Int` that don’t have `null` as a valid value. Because `orNull` is implemented using a constraint `Null <:< A`, you can still instantiate `Option[Int]`, as long as you stay away from orNull for those instances. 

Another use of type constraints is for improving type inference. Consider 

{% highlight scala %}
def firstLast[A, C <: Iterable[A]](it: C) = (it.head, it.last) 
{% endhighlight %}

When you call `firstLast(List(1, 2, 3))` you get a message that the inferred type arguments `[Nothing, List[Int]]` don’t conform to `[A, C <: Iterable[A]]`. Why `Nothing`? The type inferencer cannot figure out what `A` is from looking at `List(1, 2, 3)`, because it matches `A` and `C` in a single step. To help it along, first match `C` and then `A`: 

{% highlight scala %}
def firstLast[A, C](it: C)(implicit ev: C <:< Iterable[A]) = (it.head, it.last)
{% endhighlight %}

A type parameter can have a *context bound* of the form `T : M`, where `M` is another generic type. It requires that there is an implicit value of type `T[M]` in scope. For example, 

{% highlight scala %}
class Pair[T : Ordering] 
{% endhighlight %}

requires that there is an implicit value of type `Ordering[T]`. That implicit value can then be used in the methods of the class. Consider this example: 

{% highlight scala %}
class Pair[T: Ordering](val first: T, val second: T) {
  def smaller(implicit ord: Ordering[T]) = if (ord.compare(first, second) < 0) first else second
}
{% endhighlight %}

If we form a new `Pair(40, 2)`, then the compiler infers that we want a `Pair[Int]`. Since there is an implicit value of type `Ordering[Int]` in the `Predef` scope, `Int` fulfills the context bound. That ordering becomes a field of the class, and it is passed to the methods that need it. If you prefer, you can retrieve the ordering with the implicitly method in the `Predef` class: 

{% highlight scala %}
class Pair[T: Ordering](val first: T, val second: T) {
  def smaller = if (implicitly[Ordering[T]].compare(first, second) < 0) first else second
}
{% endhighlight %}

The implicitly function is defined as follows in `Predef.scala`: 

{% highlight scala %}
def implicitly[T](implicit e: T) = e   
// For summoning implicit values from the nether world 
{% endhighlight %}

Note: The comment is apt—the implicit objects live in the “nether world” and are invisibly added to methods. 

Alternatively, you can take advantage of the fact that the `Ordered` trait defines an implicit conversion from `Ordering` to `Ordered`. If you import that conversion, you can use relational operators: 

{% highlight scala %}
class Pair[T: Ordering](val first: T, val second: T) {
  def smaller = {
    import Ordered._; if (first < second) first else second
  }
}
{% endhighlight %}

These are just minor variations; the important point is that you can instantiate `Pair[T]` whenever there is an implicit value of type `Ordering[T]`. For example, if you want a `Pair[Point]`, arrange for an implicit `Ordering[Point]` value: 

{% highlight scala %}
implicit object PointOrdering extends Ordering[Point] {
  def compare(a: Point, b: Point) = ...
}
{% endhighlight %}

#### Evidence 
The type constraints:

{% highlight scala %}
T =:= U 
T <:< U 
T <%< U 
{% endhighlight %}

test whether `T` equals `U`, is a subtype of `U`, or is view-convertible to `U`. To use such a type constraint, you supply an implicit parameter, such as 

{% highlight scala %}
def firstLast[A, C](it: C)(implicit ev: C <:< Iterable[A]) =   
  (it.head, it.last) 
{% endhighlight %}

The `=:=`, `<:<`, and `<%<` are classes with implicit values, defined in the `Predef` object. For example, `<:<` is essentially: 

{% highlight scala %}
abstract class <:<[-From, +To] extends Function1[From, To]

object <:< {
  implicit def conforms[A] = new (A <:< A) {
    def apply(x: A) = x
  }
}
{% endhighlight %}

Suppose the compiler processes a constraint `implicit ev: String <:< AnyRef`. It looks in the companion object for an implicit object of type `String <:< AnyRef`. Note that `<:<` is contravariant in `From` and covariant in `To`. Therefore the object 

{% highlight scala %}
<:<.conforms[String] 
{% endhighlight %}

is usable as a `String <:< AnyRef` instance. (The `<:<.conforms[AnyRef]` object is also usable, but it is less specific and therefore not considered.)

We call `ev` an "evidence object" — its existence is evidence of the fact that, in this case, `String` is a subtype of `AnyRef`. Here, the evidence object is the identity function. To see why the identity function is required, have a closer look at 

{% highlight scala %}
def firstLast[A, C](it: C)(implicit ev: C <:< Iterable[A]) = (it.head, it.last) 
{% endhighlight %}

The compiler doesn’t actually know that `C` is an `Iterable[A]` — recall that `<:<` is not a feature of the language, but just a class. So, the calls `it.head` and `it.last` are not valid. But `ev` is a function with one parameter, and therefore an implicit conversion from `C` to `Iterable[A]`. The compiler applies it, computing `ev(it).head` and `ev(it).last`.

Конечно, в случае context bound'ов, в отличие от view bound'ов, не сразу понятно, как их использовать. Типичный пример из стандартной библиотеки, не связанный с type class'ами:

{% highlight scala %}
object Array {
//...
  def ofDim[T: ClassManifest](n1: Int): Array[T] =
    new Array[T](n1)
//...
}
{% endhighlight %}

Инициализация массивов Array initialization on a parameterized type requires a ClassManifest to be available, for arcane reasons related to type erasure and the non-erasure nature of arrays.

Another very common example in the library is a bit more complex:

{% highlight scala %}
def f[A : Ordering](a: A, b: A) = implicitly[Ordering[A]].compare(a, b)
{% endhighlight %}

Here, implicitly is used to retrive the implicit value we want, one of type `Ordering[A]`, which class defines the method `compare(a: A, b: A): Int`.

