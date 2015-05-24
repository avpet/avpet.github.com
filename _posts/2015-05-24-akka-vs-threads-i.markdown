---
layout: post
title:  "Потоки vs акторы - I"
date:   2015-05-24 10:30:00
categories: scala
image: http://i.imgur.com/EFaa8Mz.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

Императивное программирование базируется в первую очередь на идее последовательного выполнения и разделяемой памяти. Потоки чаще всего рассматриваются в качестве логического продолжения этих понятий, которое позволяет организовать несколько параллельных выполнений, каждое из которых является последовательным. Потоки до сих пор являются основным методом для организации параллелизма. Однако, параллельное программирование с использованием потоков, блокировок и разделяемой памяти справедливо считается трудным и чреватым ошибками. 

#### Последствия наличия разделяемой модифицируемой памяти ####

В отличие от процессов, потоки разделяют одно адресное пространство, т.е. теоретически разные потоки могут одновременно менять одни и те же участки памяти. В императивном программировании считается совершенно нормальным модифицировать одни и те же переменные, таким образом, потоки будут конкурировать при одновременном доступе на запись. Многопоточность принципиально основана на вытесняющей приоритизации. В результате, моменты переключения и чередования потоков между потоками заранее неизвестны. Это является причиной недетерминированности. Если ничего не предпринять, сочетание изменяемой памяти и недетерминированности скорее всего приведет к ситуации, называемой [race condition](http://en.wikipedia.org/wiki/Race_condition).

Например, в ситуации с разделяемой модифицируемой переменной, если мы не используем потоки, у нас будет

{% highlight scala %}
var sum=0
(1 to 10000).foreach(n=>sum+=n); println(sum)

50005000
{% endhighlight %}

Если же мы будем использовать параллельные коллекции, то получим неожиданный результат:

{% highlight scala %}
var sum=0
(1 to 10000).par.foreach(n=>sum+=n);println(sum)

49980037
{% endhighlight %}

Т.е., нам нужен механизм для защиты критических секций и обеспечения синхронизированного доступа. 

Блокировки
----------

Наиболее распространенными примитивами синхронизации являются блокировки, которые контролируют доступ к критическим секциям. Существуют различные типы блокировок, с различающимися поведением и семантикой. Например, семафоры (java.util.concurrent.locks.Lock) - простые блокировки, в которых есть два метода - `lock` (функция ожидания захвата) и `unlock` (сигнализирует об разблокировании). Существуют также подсчитывающие семафоры (counting semaphores - [`java.util.concurrent.locks.Semaphore`](https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/Semaphore.html)), позволяющие впустить в критическую секцию без ожидания только определенное количество потоков

{% highlight scala %}
import java.util.concurrent.Semaphore
import scala.concurrent._
import scala.concurrent.duration._

object SemaphoreDemo extends App {
  val semaphore = new Semaphore(10)

  import ExecutionContext.Implicits.global

  Await.result(Future {
      try {
        semaphore.acquire()
        println("Locks acquired")
        println(s"Locks remaining >> ${semaphore.availablePermits}")
      } catch { case e: InterruptedException => e.printStackTrace()
      } finally {
        semaphore.release()
        println("Locks Released")
      }
    }, 2 second)
}
{% endhighlight %}

Что выведет:

    Locks acquired
    Locks remaining >> 9
    Locks Released

Более продвинутой формой для организации взаимных исключений (mutex) является монитор, который защищает секции с использованием условных переменных, которые действуют или на уровне объекта, или метода. В Java и соответственно в Scala используется разновидность мониторов, соблюдающих семантику Mesa в противоположность семантике Хоара. Важным свойством монитора является реентерабельность - в особенности для рекурсивных функций. 

{% highlight scala %}
class BoundedBuffer[A](N: Int)(implicit m: ClassTag[A]) {
  var in = 0
  var out = 0
  var n = 0

  val elems: Array[A] = new Array[A](N)

  def put(x: A) = synchronized {
    while (n >= N) wait()
    elems(in) = x ; in = (in + 1) % N ; n = n + 1
    if (n == 1) notifyAll()
  }

  def get: A = synchronized {
    while (n == 0) wait()
    val x = elems(out) ; out = (out + 1) % N ; n = n - 1
    if (n == N - 1) notifyAll()
    x
  }
}

object BoundedBufferTest extends App {
  import ExecutionContext.Implicits.global

  val buf = new BoundedBuffer[String](10)
  Await.result(
    Future.sequence(
      Future { 1.to(10).foreach{_ => val s = produceString ; buf.put(s) }} ::
        Future { 1.to(10).foreach{_ =>  val s = buf.get ; consumeString(s) }} ::
        Nil),
    20 second)

  def produceString: String = {
    val s = Random.alphanumeric.take(10).mkString
    println(s"produced $s")
    s
  }

  def consumeString(s: String) = {
    println(s"consumed $s")
  }
}
{% endhighlight %}

что выведет что-то вроде

    produced yLMOhX7j9b
    consumed yLMOhX7j9b
    produced i1tWzCuQg7
    consumed i1tWzCuQg7
    produced 6hXjVfwjz3
    consumed 6hXjVfwjz3
    produced DchL8Kxakl
    consumed DchL8Kxakl
    produced 2YTHcRl8Ig
    produced cRXBB75Hur
    consumed 2YTHcRl8Ig
    consumed cRXBB75Hur
    produced qjdzDn2Sf6
    consumed qjdzDn2Sf6
    produced nuHNsoGXpU
    consumed nuHNsoGXpU
    produced HX6AQAIgd3
    produced q1pV1u0nQx
    consumed HX6AQAIgd3
    consumed q1pV1u0nQx


Кроме подсчитывающих блокировок, существуют блокировки, которые ведут себя по-разному в зависимости от режима доступа. Блокировки чтения/записи разрешают одновременный доступ на чтение, но запрещают доступ на запись.

#### Проблемы с блокировками ####

Приведем пример с очень упрощенной реализацией поискового движка

Сначала - вообще без синхронизации. Движок использует инвертированный индекс. Наш инвертированный индекс отображает части имени на объекты `User`.

Нашей разделяемой памятью в данном случае является `userMap`. Если бы мы использовали только один поток, то мы бы могли просто использовать `mutable.HashMap`.

{% highlight scala %}
import scala.collection.mutable

case class User(name: String, id: Int)

class InvertedIndex(val userMap: mutable.Map[String, User]) {

  def this() = this(new mutable.HashMap[String, User])

  def tokenizeName(name: String): Seq[String] = {
    name.split(" ").map(_.toLowerCase)
  }

  def add(term: String, user: User) {
    userMap += term -> user
  }

  def add(user: User) {
    tokenizeName(user.name).foreach { term =>
      add(term, user)
    }
  }
}
{% endhighlight %}

Конечно, в контексте многопоточного доступа `userMap` является незащищенным. Таким образом, мы добавляем блокировку на него:

{% highlight scala %}
def add(user: User) {
  userMap.synchronized {
    tokenizeName(user.name).foreach { term =>
      add(term, user)
    }
  }
}
{% endhighlight %}

Блокировки позволяют нам  выстроить последовательно доступ к критическим секциям; аккуратно расставляя блокировки, мы уменьшаем неопределенность и гарантируем последовательный доступ. К сожалению, такая блокировка является слишком крупной - всегда желательно делать насколько возможно меньше работы внутри мьютекса. Блокировка является сравнительно дешевой операцией, если у нас нету одновременного доступа к разделяемому ресурсу. Чем меньше работы делается внутри критической секции, тем меньше конфликт доступа. Блокировки, которые включают слишком много кода, снижают параллелизм.

{% highlight scala %}
def add(user: User) {
  val tokens = tokenizeName(user.name)

  tokens.foreach { term =>
    userMap.synchronized {
      add(term, user)
    }
  }
}
{% endhighlight %}

Для большего параллелизма, выбор блокировок должен быть очень осторожным. Большое количество критических секций не просто увеличивают накладные расходы на управление блокировками, оно может привести к появлению других проблем, связанных с неправильными блокировками, например, если вдруг блокировка не будет освобождена, и значит ее не удастся получить другому потоку. Из проблем, которые могут потенциально возникнуть, можно упомянуть:  

* взаимоблокировка ([deadlock](http://en.wikipedia.org/wiki/Deadlock)),  возникающая в случае потоков, пытающихся получить доступ к блокировкам с циклическими зависимостями
* динамическая взаимоблокировка ([livelock](http://en.wikipedia.org/wiki/Deadlock#Livelock)) - ситуация, когда потоки непрерывно меняют своё состояние в ответ на изменения в другом потоке, не производя полезной работы. Т.е., в отличие от взаимоблокировки, каждый процесс ждет, так сказать, “активно”, пытаясь все-таки решить проблему самостоятельно (например, делая новые попытки захватить ресурс раз за разом). Причиной динамической взаимоблокировки обычно становится комбинация вот таких усилий потоков по разрешению проблемы при доступу к ресурсу.

В сумме нужно заметить, что программирование с использованием блокировок, хотя и остается все еще самым популярным видом многопоточного программирования, является делом очень сложным, а следовательно, цена поддержки таких решений очень высока. 

#### Параллельное выполнение задач ####

Задача - единица работы, в идеале автономная, выполняющая некоторое действие или вычисление. Например, задача может вычислять простые числа в некотором диапазоне. Автономность ценна потому, что тогда задачи можно распараллелить и выполнять в разных потоках. Например, задачу можно оформить как [`Runnable`](https://docs.oracle.com/javase/7/docs/api/java/lang/Runnable.html), и запустить на выполнение в некотором пуле потоков. Для этого в Java есть абстракция [`Executor`'а](http://docs.oracle.com/javase/7/docs/api/java/util/concurrent/Executor.html):

{% highlight java %}
public interface Executor {
    void execute(Runnable command);
}
{% endhighlight %}

и [ExecutorService'а](http://docs.oracle.com/javase/7/docs/api/java/util/concurrent/ExecutorService.html). Например, представим себе, что мы хотим заполнить наш поисковый движок с инвертированным индексом данными из текстового файла. 

{% highlight scala %}
class ConcurrentInvertedIndex(userMap: ConcurrentHashMap[String, User]) extends InvertedIndex(userMap.asScala) {
  def this() = this(new ConcurrentHashMap[String, User] asScala)
}

trait UserMaker {
  def makeUser(line: String) = line.split(",") match {
    case Array(name, userid) => User(name, userid.trim().toInt)
  }
}

class FileRecordProducer(path: String) extends UserMaker {
  val index = new ConcurrentInvertedIndex()

  def run() {
    Source.fromFile(path, "utf-8").getLines.foreach { line =>
      index.add(makeUser(line))
    }
  }
}
{% endhighlight %}

Очевидно, что это можно было бы сделать эффективнее - парсинг и индексация отдельной строки не зависит от индексации других строк, поэтому каждая индексация можно быть отдельной задачей. Чтобы сделать индексацию независимой от ввода-вывода, мы используем паттерн "producer-consumer", где producer генерирует данные и записывает их в очередь, а consumer'ы вычитывают очередь и индексируют данные. 

{% highlight scala %}
import java.util.concurrent.Executors

import scala.io.Source

object ProducerConsumer extends App {
  import java.util.concurrent.{BlockingQueue, LinkedBlockingQueue}

  val index = new ConcurrentInvertedIndex()

  class Producer[T](path: String, queue: BlockingQueue[T]) extends Runnable {
    def run() {
      Source.fromFile(path, "utf-8").getLines.foreach { line =>
        queue.put(line.asInstanceOf[T])
      }
    }
  }

  abstract class Consumer[T](queue: BlockingQueue[T]) extends Runnable {
    def run() {
      while (true) {
        val item = queue.take()
        consume(item)
      }
    }

    def consume(x: T)
  }

  val queue = new LinkedBlockingQueue[String]()

  val producer = new Producer[String]("users.txt", queue)
  new Thread(producer).start()

  trait UserMaker {
    def makeUser(line: String) = line.split(",") match {
      case Array(name, userid) => User(name, userid.trim().toInt)
    }
  }

  class IndexerConsumer(index: InvertedIndex, queue: BlockingQueue[String]) extends Consumer[String](queue) with UserMaker {
    def consume(t: String) = index.add(makeUser(t))
  }

  val cores = 8
  val pool = Executors.newFixedThreadPool(cores)

  for (i <- 0 to cores) {
    pool.submit(new IndexerConsumer(index, queue))
  }
}
{% endhighlight %}

Если у нас есть `n` занятых на 100% обработкой, то такого подхода, возможно, было бы достаточно. Но в реальной жизни загрузка часто распределяется неравномерно. Для этого можно воспользоваться подходом, который называется "перехват работы" ([work stealing]([http://en.wikipedia.org/wiki/Work_stealing]) - особая политика управлением распределением задач в пуле потоков; каждый процессор системы имеет стек для хранения списка готовых задач (ready queue), причём эти стеки действуют как двусторонние очереди (deque), допускающие выборку таких задач с любого конца. Свободный процессор может попытаться через планировщик перехватить у какого-то другого процессора его низкоприоритетную задачу, выбирая её с противоположного конца очереди - благодаря этому повышается общая производительность системы. Подобное реализовано в [`ForkJoinPool`](https://docs.oracle.com/javase/8/docs/api/java/util/concurrent/ForkJoinPool.html), который появился в Java 7.

#### Отказ от разделяемой памяти ####

Поскольку, как мы уже поняли, системы с использованием разделяемой памяти программировать иногда сложно (хотя это не значит, что этого делать не нужно, в некоторых случаях это просто необходимо), был сформулирован несколько другой подход, связанный с передачей сообщений. 
Многопоточность с передачей сообщений ([Message passing concurrency](http://c2.com/cgi/wiki?MessagePassingConcurrency)) - подход, при котором потоки не обращаются к разделяемой памяти, а при необходимости обменяться данными отсылают друг другу помощью сообщения, содержащие необходимые данные. 

*Message passing concurrency* имеет следующие преимущества:

* Такой подход легче моделируется, т.е. в его терминах проще проводить рассуждения; существуют как минимум несколько формальных моделей Message passing concurrency ([Communicating Sequential Processes](http://en.wikipedia.org/wiki/Communicating_sequential_processes), [Actors](http://en.wikipedia.org/wiki/Actor_model), [π-calculus](http://en.wikipedia.org/wiki/%CE%A0-calculus), [Join calculus](http://en.wikipedia.org/wiki/Join-calculus)).
* Синхронизация между потоками осуществляется передачей сообщений, а значит, не нужно заботиться о взаимных исключениях; каждый поток имеет свое состояние, которое доступно только ему одному;
* Хорошо подходит для распределенных систем.

Возможные недостатки:

* Теоретически является менее производительным, чем подход с разделяемой памятью

* В то время как данные, не содержащие ссылок, ложатся хорошо в эту модель, особая осторожность требуется при попадании в сообщение данных, содержащих ссылки в каком-либо виде.

Нас интересует именно модель акторов. Что такое актор?  

В модели акторов, актор - основной элемент вычислений, состоящий из 3 частей:

1. Обработчика
2. Памяти
3. Способностью связи с помощью сообщений

Как все это связано с многопоточностью? Дело в том, что сам по себе один единственный актор не очень полезен. Акторы приобретают свои полезные качества, будучи объединенными в **системы**. Чтобы в пределах системы к ним можно было бы обращаться, у них должны быть **адреса**. Актор может послать сообщение другому актору, причем, как в случае с факториалом, этот другой может быть самим исходным актором - так реализуется рекурсия. 

Пример использования акторов для вычисления факториала в нескольких потоках. 

{% highlight scala %}
import scala.annotation.tailrec

import akka.actor.{Actor, ActorLogging, ActorSystem, Props}

object Factorial extends App {
  val factorials = List(20, 18, 32, 28, 22, 42, 55, 48)

  val system = ActorSystem("factorial")

  val collector = system.actorOf(Props(new FactorialCollector(factorials)), "collector")
}

case class FactorialRequest(num: Int)

case class FactorialResponse(num: Int, result: BigInt)

class FactorialCollector(factorials: List[Int]) extends Actor with ActorLogging {
  var list: List[BigInt] = Nil

  for (num <- factorials) {
    context.actorOf(Props(new FactorialCalculator)) ! FactorialRequest(num)
  }

  def receive = {
    case FactorialResponse(num, fac) => {
      log.info(s"factorial for $num is $fac")

      list = num :: list

      if (list.size == factorials.size) {
        context.system.shutdown()
      }
    }
  }
}

class FactorialCalculator extends Actor {
  def receive = {
    case FactorialRequest(num) => sender ! FactorialResponse(num, factor(num))
  }

  private def factor(num: Int) = factorTail(num, 1)

  @tailrec private def factorTail(num: Int, acc: BigInt): BigInt = {
    (num, acc) match {
      case (0, a) => a
      case (n, a) => factorTail(n - 1, n * a)
    }
  }
}
{% endhighlight %}

Здесь мы задаем список чисел `factorials`, для каждого из которого мы хотим вычислить факториал в отдельном потоке. Далее, мы создаем управляющий  фактор, `FactorialCollector`, и передаем на вход наш список. 

`FactorialCollector` хранит некоторое состояние, `factorials` - список результатов, `list` - список результатов. Состояние актора принадлежит только ему и никакому другому актору более, поэтому нас не волнуют конфликты доступа. `FactorialCollector` запускает несколько акторов `FactorialCalculator`, по одному на каждое число во входном списке. В частично определенной функции `receive` (в которой заявляется, какие сообщения мы можем обработать и как именно мы это собираемся делать). `FactorialCollector` принимает сообщения типа `FactorialResponse`.

Таким образом, `FactorialCollector` разбрасывает нагрузку по параллельно выполняющимся акторам и ждем прибытия результатов. В данном случае `FactorialCollector` является **супервизором** для акторов `FactorialCalculator`, т.е. делегирует задачи своим подчиненным и является ответственным за возникающие в подчиненных акторах проблемы, т.е. в идеале он должен на них реагировать - или передать своему супервизору, если таковой у него есть. Если в подчиненном акторе возникает проблема (например, выбрасывается исключение), он приостанавливает свое выполнение и всех своих подчиненных акторов и отсылает сообщение своему супервизору, сигнализируя о проблеме.

Метод `receive` актора `FactorialCollector` ждет результатов от своих подчиненных `FactorialCalculator` акторов; если все результаты получены, актор останавливает `ActorSystem`. 

Вообще, получив сообщение, актор может: 

1. Создать конечное количество других акторов 
 
2. Послать конечное количество сообщений другим акторам, адреса (`ActorRef`) которых у него есть. 

3. Актор может менять собственное поведение и процесс обработки следующих сообщений, которые он получит. Однако здесь есть ограничение, что он должен как минимум поддерживать обработку тех сообщений, которые уже поддерживались, чтобы не сломать совместимость.

Один актор обрабатывает одно сообщение за раз, но, как видно из примера с факториалом, мы организуем иерархию взаимодействующих акторов и таким образом организовать многопоточную обработку. 

#### Однопоточность в акторе - mailbox ####

Как же обеспечивается однопоточность в акторе?  Фактически, за счет того, как работает почтовый ящик актора (mailbox), который представляет собой очередь, и который согласно модели акторов, вычитывается последовательно. Хотя, конечно, это можно обойти при желании, но в нарушение правил и в таком случае никакие гарантии потокобезопасности модели уже неприменимы.

{: .center}
![2b8zVSb.png](http://i.imgur.com/2b8zVSb.png)

В том числе и по этой причине был придуман [`ActorRef`](http://doc.akka.io/api/akka/2.0/akka/actor/ActorRef.html) - адрес, или дескриптор, который позволяет общаться с актором посредством передачи сообщений, но который не позволяет напрямую обратиться к актору.

Каждый актор имеет один mailbox (он может в некоторых ситуациях совместно использоваться несколькими акторами, но как правило, это связь один к одному). Порядок сообщений же соблюдается только если последовательность сообщений была отослана от одного актора - сообщения от нескольких акторов придут в непредсказуемом порядке.

