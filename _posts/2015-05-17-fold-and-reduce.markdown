---
layout: post
title:  "Fold, aggregate, reduce и scan - III"
date:   2015-05-17 20:30:00
categories: scala
image: http://i.imgur.com/9EuOOe1.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>


### Параллельные коллекции и свертка

Начиная с версии 2.9, в Scala была добавлена поддержка параллельных коллекций. Сама по себе эта тема довольно большая, но для простоты можно сказать, что некоторые операции подобных коллекций выполняются в параллель. Разбиение на пакеты и иерархия классов параллельных коллекций (`scala.collection.parallel`) в общем и целом напоминает организацию непараллельного `scala.collection` с разбиением на мутабельные и иммутабельные типы. При этом они не являются подтипами нормальных коллекций, а вместо этого у нормальных и параллельных коллекций есть общие трейты-родители, названия которых, как правило, начинаются с префикса `Gen`. Названия параллельных коллекций начинаются с префикса `Par`.

Преобразование уже существующей коллекции в параллельую и назад делается соотвественно вызовами методов `par` и `seq` из трейта [`Parallelizable`](http://www.scala-lang.org/api/2.11.5/index.html#scala.collection.Parallelizable). 

{% highlight scala %}
scala> 1 to 10 par
res0: scala.collection.parallel.immutable.ParRange = ParRange(1, 2, 3, 4, 5, 6, 7,
8, 9, 10)
scala> Array(1,2,3,4) par
res1: scala.collection.parallel.mutable.ParArray[Int] = ParArray(1, 2, 3, 4)
scala> val parSeq = List(1,2,3,4).par
parSeq: scala.collection.parallel.immutable.ParSeq[Int] = ParVector(1, 2, 3, 4)
scala> parSeq.seq
res0: scala.collection.immutable.Seq[Int] = Vector(1, 2, 3, 4)
{% endhighlight %}


Параллельные коллекции имеют те же методы, что и нормальные коллекции, но уже с другими реализациями. 

Например, для того, чтобы вычислить факториал в несколько потоков, достаточно написать:

{% highlight scala %}
def parFact(n:BigInt) = (BigInt(1) to n).par.product
{% endhighlight %}

Для сравнения, если бы мы задались целью написать свою многопоточную версию версию вычисления факториала, то получилось бы что-то вроде:

{% highlight scala %}
object ParallelFactorial {

  val numThreads:Int = 10
  import ExecutionContext.Implicits.global

  def parallelFactorial(n: Int): BigInt = {
    val blocks = splitIntoBlocks[BigInt]((BigInt(1) to BigInt(n)).toList, numThreads)
    val f = Future.sequence(blocks.map {b => Future (b.product) })
    Await.result(f.map(results => results.product), Duration(120, TimeUnit.SECONDS))
  }

  private def splitIntoBlocks[A](xs: Seq[A], n: Int) = {
    val m = xs.length
    val targets = (0 to n).map{x => math.round((x.toDouble*m)/n).toInt}
    def snip(xs: Seq[A], ns: Seq[Int], got: Vector[Seq[A]]): Vector[Seq[A]] = {
      if (ns.length<2) got
      else {
        val (i,j) = (ns.head, ns.tail.head)
        snip(xs.drop(j-i), ns.tail, got :+ xs.take(j-i))
      }
    }
    snip(xs, targets, Vector.empty)
  }
}
{% endhighlight %}
 

Очевидно, что версия с использованием параллельной коллекции выглядит тривиальной, с точки зрения клиента. Это и являлось целью создания фреймворка параллельных коллекций - сделать многопоточное програмиирование более доступным, потому что очевидно, что при многопоточном программировании используются несколько другие алгоритмы и структуры данных. Но некоторые вещи, тем не менее, можно обобщить - например, явно присутствет фазы разделения входной коллекции на части, обработка частей в отдельных потоках, а затем сборка финального результата. За реализацию этих фаз во фреймворке параллельных коллекций отвечают: 

* [`Splitter`](http://www.scala-lang.org/api/2.11.5/index.html#scala.collection.parallel.Splitter)  -который отвечает за разбивку коллекции; яляется также итератором.

* [`Combiner`](http://www.scala-lang.org/api/2.11.5/index.html#scala.collection.parallel.Combiner) - который соотвествует [`Builder`](http://www.scala-lang.org/api/2.11.5/index.html#scala.collection.mutable.Builder) у в последовательных коллекциях, и имеет метод `combine`, который принимает на вход другой `Combiner`.

и возвращает новый, содержащий объединение элементов обоих (более подробно см. [здесь](http://docs.scala-lang.org/overviews/parallel-collections/overview.html), [здесь](http://www.scala-lang.org/api/2.11.5/index.html#scala.collection.parallel.ParIterable)) и [здесь](http://infoscience.epfl.ch/record/150220/files/pc.pdf).

Параллелизм в параллельных коллекциях реализован в стиле "divide and conquer", т.е. исходная коллекция разбивается на меньшие части, и уже эти части обрабатываются последовательно.

Параллельные операции оформляются как задачи (см. [`scala.collection.parallel.Task`](http://www.scala-lang.org/api/2.11.5/index.html#scala.collection.parallel.Task)). `Task`s передаются на выполнение объекту [`scala.collection.parallel.TaskSupport`](http://www.scala-lang.org/api/2.11.5/index.html#scala.collection.parallel.TaskSupport), который может быть сконфигурирован для коллекции. Примером конкретной реализации `TaskSupport` явлеятся `ForkJoinTaskSupport`.

Конечно, нужно при этом помнить, что любой дополнительный абстрактный слой имеет определенную цену, да и сама многопточность имеет некоторые накладные расходы, поэтому выбор  - использовать параллельную версию или нет, должен основываться на замерах производительности.

Теперь о свертке. Как ясно из названия, методы `foldLeft`, `foldRight`, `reduceLeft`, и `reduceRight` - связаны с последовательной обработкой; фактически они делегируют вызовы в соотвествующую последовательную реализацию, т.е. параллельными не являются. Паралелльными являются методы   метод `fold`, `reduce` и `aggregate`. 

{% highlight scala %}
scala> val sum = Array(1,2,3).par.reduce(_ + _)
sum: Int = 6
{% endhighlight %}

Результат этой операции будет совпадать с результатом вызова `reduceLeft`. Вообще, нужно заметить, что секции, на которые будет разбита коллекция, будут в конце концоы смерджены в результате таким образом, что будет выглядеть так, что вроде бы порядок обхода был сохранен, хотя эти секции реально выполнялись и не по порядку - и это верно для всех трех операций - `fold/aggregate/reduce`. Трюк состоит в том, что операция, которая используется в свертке (`_ + _` в данном случае) должна быть ассоциативной, т.е. позволять произвольные разбиения и перегруппировки (т.е. как произойдет разбиение на группы, заранее неизвестно), но с сохранением порядка - например, `1, 2, 3`, может быть сведен в `(1 + 2) + 3` или `1 + (2 + 3)`, но не в `(2 + 1) + 3`. При этом операция не должна быть коммутативной. Пример такой операции - конкатенация строки:

{% highlight scala %}
"acbdefgh".par.map(_.toString).reduce(_+_)
{% endhighlight %}

И `fold`, и `aggregate` могут выполнять работу в параллель: каждый из них обходит элементы в разных группах последовательно, и затем группы мерджаться так, что первоначальный порядок сохранен (хотя то, как происходит разбиение на группы, мы не знаем).
Например, возьмем список `List("a","b","c","d")` - сначала он может быть разбит на группы `"a"+"b"` и `"c"+"d"`, которые будут орбработаны параллельно, причем `"c" + "d"` а затем `"a"+"b"`, а затем будет выполено слияние `"ab"+"cd"`, причем в результате порядок сохранен.

Но в то время как метод `reduce` является полной заменой для `reduceLeft` или `reduceRight` в ситуациях, когда для нас не важен порядрк обработки, и то с как мы уже видели в 1-й части, ситуация с `fold` несколько сложнее  - достаточно сравнить сигнатуры `fold` and `foldLeft` из трейта `ParIterable[T]`:

{% highlight scala %}
def fold [U >: T] (z: U)(op: (U, U) U): U
def foldLeft [S] (z: S)(op: (S, T) S): S
{% endhighlight %}

Метод `fold` более ограничен в отношении типов, которые он может использовать. В то время как в `foldLeft` типы элементов, с одной стороны, и аккумулятора и результата, с другой совершенно разные и никак не связаны между собой, в `fold` тип результата должен быть предком типа элементов. 

Причина ограничения именно в многопоточном варианте - в однопоточном этой проблемы нет. В то время как один поток работает над одной секцией, другой поток  - над другой, и не понятно, какой из них закончит раньше, то операция `op` должна быть коммутативной, т.е. возможна как ситуация `op(a,b)`, так и `op(b,a)` - в отличие от ситуации с `foldLeft`. Это можно сделать двумя путями - либо наложить ограничение на типы (как это сделано в `fold`), либо предоставить дополнительную операцию для комбинирования - как это сделано в `aggregate`:

{% highlight scala %}
def aggregate [B] (z: B)(seqop: (B, A) ⇒ B, combop: (B, B) ⇒ B): B
{% endhighlight %}

Здесь `A` - тип элементов коллекции, `B` - тип аккумулятора и результата. Допустим, у нас есть четыре элемента. Тогда возможен следующий сценарий работы `aggregate`:

{: .center}
![LiJdm4J.png](http://i.imgur.com/LiJdm4J.png)


Например, путь есть набор слов `GenSeq("I", "have", "a", "dream")`, и мы хотим узнать, сколько букв в этих словах в общей сложности.

{% highlight scala %}
import scala.collection.GenSeq
val seq = GenSeq("I", "have", "a", "dream")
val chars = seq.aggregate(0)(_ + _.length, _ + _)
{% endhighlight %}

Сначала, в первый проход, мы, например, получаем:

{% highlight scala %}
0 + "I".length       // 1
0 + "have".length    // 4
0 + "a".length       // 1
0 + "dream".length   // 5
{% endhighlight %}

Затем мы, возможно, получим:

{% highlight scala %}
4 + 2 // 5
2 + 7 // 6
{% endhighlight %}

И как последний шаг

{% highlight scala %}
5 + 6 // 11
{% endhighlight %}

и мы получили результат. Т.е. мало того, что у нас получилось 3 прохода (благодаря параллелизму) вместо 7 в случае последовательной реализации, в случае `aggregate` мы, предоставив `combop`, получаем гибкость в использовании типов.

### Option.fold

Операция `fold` есть также в `Option`е, но работает она немного неожиданным образом. 

{% highlight scala %}
@inline final def fold[B](ifEmpty: => B)(f: A => B): B
{% endhighlight %}

`Option.fold` делает одно из двух: или вызывает функцию `f` со значением `Option`а - если оно есть, или возвращает другое значение `ifEmpty`, если в нем содержится `None`. Т.е. фактически это комбинация `map` и `getOrElse`:

{% highlight scala %}
val x: R = option map f getOrElse ifEmpty
{% endhighlight %}

С `Option.fold` же это выглядит так:

{% highlight scala %}
val x: R = option.fold(ifEmpty)(f)
{% endhighlight %}

В данном случае аналогия с `fold`, который есть у коллекций, несколько натянутая, даже если представить, что `Option` является коллекцией с количеством элементов более от 0 до 1. Для данного метода бы лучше подошло бы название `mapOrElse`.

