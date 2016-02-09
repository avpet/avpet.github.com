---
layout: post
title:  "Коллекции: CanBuildFrom, map и Builder - I"
date:   2016-01-16 11:30:00
categories: scala
image: http://imageshack.com/a/img905/4510/8e7vkO.png
---

Источники:

* [https://en.wikipedia.org/wiki/Polymorphism_(computer_science)](https://en.wikipedia.org/wiki/Polymorphism_(computer_science))
* [https://www.manning.com/books/scala-in-depth](https://www.manning.com/books/scala-in-depth)
* [http://danielwestheide.com/blog/2013/02/06/the-neophytes-guide-to-scala-part-12-type-classes.html](http://danielwestheide.com/blog/2013/02/06/the-neophytes-guide-to-scala-part-12-type-classes.html)
* [https://www.safaribooksonline.com/blog/2013/05/28/scala-type-classes-demystified/](https://www.safaribooksonline.com/blog/2013/05/28/scala-type-classes-demystified/)

Из презентации Одерского [Scala - the Simple Parts](https://www.youtube.com/watch?v=ecekSCX3B4Q):

> "One argument that you hear sometimes is that people say that type of `map` \[method\] is ugly or a lie. To explain that let's lookup the scala doc... of `map` and lookup the one for `Array`s:

{% highlight scala %}
def map[B](f: A => B): Array[B]
{% endhighlight %}
*\[use case\] Builds a new collection by applying a function to all elements of this array.*

> `map` takes the type parameter `B`, the function from `A` to `B` that gives you back an `Array[B]`. Looks reasonable, right? But there is this ominous thing which tells that says - *use case*. What this does says that in principle that if I am a client, then that's the type I need to know. That' how arrays work for me, from the client perspective. But what actually happens is that if you lookup the implementation of `map` you won't find it in `Array` = you will find 
it in much more general space where it works for all collections. And that's very important because... every collection \[before Scala 2.8\] had their own `map` implementation, and that lead to a lot of... discrepancy creep between 
collections... This makes things hard to use. You don't have the smae operations,... so what we have decided it would be much better if there would be... a single reference implementation of every method you have in collection. Some 
times the reference implementation is overwritten in particular collection for performance reasons, but there should be a single reference implementation. Now if you look up that type, 

{% highlight scala %}
def map[B, That](f: (T) => B)(implicit bf: CanBuildFrom[Array[T], B, That]): That 
{% endhighlight %}

> Now there are two type parameters `B` and  `That`, and here's the function that goes from `T` to `B`, and there is this implicit parameter which is called `CanBuildFrom`, if you have an `Array` of type `T` and element type `B` and if 
> you want to build the collection of type `That`, then that's what you return."

Хотя в своей практике программист, как правило, редко сталкивается с `CanBuildFrom` непосредственно - если он не создает свои коллекции или не интересуется их архитектурой, тем не менее, для понимания архитектуры коллекций `CanBuildFrom` играет важную роль. Сама по себе `CanBuildFrom` - сравнительно простая вещь сама по себе: имея экземпляр `CanBuildFrom` для коллекции данного типа, мы можем получить `Builder` для данной коллекции. Имея `Builder`, мы можем просто добавлять элементы, и в конце получить желаемую коллекцию. Как следствие, с помощью метода `map` можно вернуть коллекцию любого типа, отличного от типа исходной коллекции, причем результирующий тип может быть даже не в стандартной библиотеке - достаточным условием является наличие `CanBuildFrom` для типа коллекции. Например, этот подход можно применить к обычному `Array` из JDK, поскольку в библиотеке Scala есть соответствующий `CanBuildFrom`. 

Конечно, теоретически модно было бы огранчить `map` таким образом, что он бы возвращал тот же самый тип коллекции, что и принимал на вход. В таком случае, для bit set'ов `map` принмал бы только функции типа `f: Int => Int`, а для `Map`  - исключительно `f: (A, B) => (A, B)`. Но такой подход не только нежелателен с точки зрения объектно ориентированного моделирования, он вообще некорректен, потому что нарушает принцип подстановки Барбары Лисков: ведь поскольку `Map` есть `Iterable`, то  любая операция, уместная для `Iterable`, должна работать и для `Map`.

API коллекций в библиотеке Scala содержит большое количество операций, унифицированных для самых различных реализаций коллекций. Реализация каждой операции заново для некоторого нового типа коллекций привело бы к большому количеству однотипного кода и даже дублированию. А это в свою очередь бы привело со временем к несоответствиям в API, поскольку добавление новых или изменение существующих операций могут касаться только некторых коллекций библиотеки, но совершенно никак не затрагивать других. Поэтому основной целью фреймыорка коллекий было избежание дублирования путем объявления операций в насколько возможно меньшем количестве мест - в идеале только в одном, но это не всегода осуществимо. Подход к дизайну заключался в том, что как можно большее количество операций определить в "шаблонах", которые бы гибко могли быть использованы путем наследования отедльных базовых классов и реализаций. 

#### Builder

{% highlight scala %}
package scala.collection.generic

class Builder[-Elem, +To] {
  def +=(elem: Elem): this.type
  def result(): To
  def clear()
  def mapResult(f: To => NewTo): Builder[Elem, NewTo] = ...
}
{% endhighlight %}

Почти все операции в коллекциях реализованы в терминах traversal'ов (проходов по коллекции) и builder'ов. Проходы осуществляются, например, с помощью метода `foreach`, а создание новых экземпляров коллекций осуществляются с помощью класса `Builder`, и выше приведена его сокращенная  - для ясности - версия.

Элемент `x` можно добавить к билдеру `b` с помощью выражения `b += x`, также есть синтаксис для добавления нескольких элементов сразу? например, для буферов - `b += (x, y)`, and `b ++= xs`, вообще, буферы являются расширенной версией builder'ов. Метод `result()` builder'а вернет искомую коллекцию. После того, как вызван метод `result()`, builder находится в неопределенном состоянии, и для очистки нужно вызвать метод `clear()`. Builder'ы являются общими (т.е. тип не зафиксирован и может быть передан) как в отношении типа элмента, `Elem`, так и в отношении типа возвращаемой коллекции `To`.

Часто, builder может использовать другой builder для построения коллекции, и затем трансформировать промежуточный результат в другой тип. Делается это с помощью метода `mapResult` в классе `Builder`. Представим себе, что у нас есть `ArrayBuffer`. `ArrayBuffer`'ы сами по себе являются builder'ами, поэтому вызов `result()` у него вернет тот же самый буфер. Если мы хотим использовать этот буфер для создания билдера, который будет нам возвращать `Array`и, мы можеи достичь этого с помощью метода `mapResult`:

{% highlight scala %}
scala> val buf = new ArrayBuffer[Int]
buf: scala.collection.mutable.ArrayBuffer[Int] = ArrayBuffer()
  
scala> val bldr = buf mapResult (_.toArray)
bldr: scala.collection.mutable.Builder[Int,Array[Int]]
  = ArrayBuffer()
{% endhighlight %}

The result value, bldr, is a builder that uses the array buffer, buf, to collect elements. When a result is demanded from bldr, the result of buf is computed, which yields the array buffer buf itself. This array buffer is then mapped with _.toArray to an array. So the end result is that bldr is a builder for arrays. 

