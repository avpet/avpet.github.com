---
layout: post
title:  "Акторы и их жизненный цикл - IV"
date:   2015-12-20 19:30:00
categories: scala
image: http://i.imgur.com/pzn4gyb.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

### Тестирование жизненного цикла актора - ActorLifeCycleSpec  ###

Актор может быть остановлен с помощью вызова метода `stop` из `ActorRefFactory`, т.е. `ActorContext` или `ActorSystem` - в зависимости от того, нужно ли актору остановить самого себя и child-акторы, или нужно остановить один из акторов верхнего уровня. Собственно остановка актора происходит асинхронно.

{% highlight scala %}
    "invoke preRestart, preStart, postRestart when using OneForOneStrategy" in {
      filterException[ActorKilledException] {
        val id = newUuid.toString
        val supervisor = system.actorOf(Props(classOf[Supervisor], OneForOneStrategy(maxNrOfRetries = 3)(List(classOf[Exception]))))
        val gen = new AtomicInteger(0)
        val restarterProps = Props(new LifeCycleTestActor(testActor, id, gen) {
          override def preRestart(reason: Throwable, message: Option[Any]) { report("preRestart") }
          override def postRestart(reason: Throwable) { report("postRestart") }
        }).withDeploy(Deploy.local)
        val restarter = Await.result((supervisor ? restarterProps).mapTo[ActorRef], timeout.duration)

        expectMsg(("preStart", id, 0))
        restarter ! Kill
        expectMsg(("preRestart", id, 0))
        expectMsg(("postRestart", id, 1))
        restarter ! "status"
        expectMsg(("OK", id, 1))
        restarter ! Kill
        expectMsg(("preRestart", id, 1))
        expectMsg(("postRestart", id, 2))
        restarter ! "status"
        expectMsg(("OK", id, 2))
        restarter ! Kill
        expectMsg(("preRestart", id, 2))
        expectMsg(("postRestart", id, 3))
        restarter ! "status"
        expectMsg(("OK", id, 3))
        restarter ! Kill
        expectMsg(("postStop", id, 3))
        expectNoMsg(1 seconds)
        system.stop(supervisor)
      }
    }
{% endhighlight %}

Если в момент остановки обрабатывалось сообщение, оно будет обработано до конца, и только последующие сообщения уже не будут обрабатываться - по умолчанию, они отправятся специальному синтетическому актору `deadLetters`. 

Остановка актора происходит в два шага: сперва актор приостанавливает обработку сообщений из mailbox'а, а затем посылает сигнал остановки всем своим child-акторам, после этого обрабатывает внутренние нотификации остановки от child-акторов, и наконец, останавливается сам. При этом вызывается `postStop`, уничтожается mailbox, и сообщение `Terminated` отправляется компонентом `DeathWatch` родителю актора. В принципе, таким образом родитель может отслеживать момент остановки child-актора, например, вот так

{: .center}
![HYWvR2m.png](http://i.imgur.com/HYWvR2m.png)

{% highlight scala %}
object TerminationExample extends App {

  val system = ActorSystem("system")

  class ActorB extends Actor {
    def receive = {
      case _ =>
    }

    override def postStop() {
      println("postStop B")
    }
  }

  class ActorA extends Actor {
    val actorB = context.actorOf(Props[ActorB])
    context.watch(actorB)

    def receive = {
      case Terminated(actor) =>
        println("supervised terminated :" + actor)
    }

    override def postStop() {
      println("postStop A")
    }
  }

  val actorA = system.actorOf(Props(classOf[ActorA]))

  system.registerOnTermination(println("System shutdown"))
  system.shutdown()
}
{% endhighlight %}

но вообще мониторинг - отдельная тема, и в данном примере получение сообщения `Terminated` не гарантировано.

#### Когда вызывается postStop? ####

В предыдущем фрагменте `postStop` актора вызывается, когда останавливается `ActorSystem`. Помимо этого, есть еще несколько ситуаций:

*ActorSystem.stop()*

Актор можно остановить, используя метод `stop` или `ActorSystem`, или `ActorContext`.

{% highlight scala %}
object StoppingDemoApp extends App{

  val actorSystem=ActorSystem("LifecycleActorSystem")
  val lifecycleActor=actorSystem.actorOf(Props[LifecycleDemoLoggingActor],"lifecycleActor")

  actorSystem.stop(lifecycleActor)

}
{% endhighlight %}

*ActorContext.stop*

Например, мы можем послать сообщение актору, в ответ на которое он остановит себя:

{% highlight scala %}
class LifecycleDemoLoggingActor extends Actor with ActorLogging {

  def receive = LoggingReceive {
    case "hello" => log.info("hello")
    case "stop" => context.stop(self)
  }
}
{% endhighlight %}

и

{% highlight scala %}
object StoppingDemoApp2 extends App {

  val actorSystem = ActorSystem("LifecycleActorSystem")
  val lifecycleActor = actorSystem.actorOf(Props[LifecycleDemoLoggingActor], "lifecycleActor")

  lifecycleActor ! "stop"
}
{% endhighlight %}

*PoisonPill*

Но вообще говоря, такое сообщение уже есть в Акке, которое приблизительно так и работает - получивший его актор вызывает `context.stop`. Сообщение `PoisonPill`, как и любое другое сообщение - как например, предыдущее сообщение `"stop"`, оно ставится в очередь в mailbox и обрабатывается в  свое время.

{% highlight scala %}
object StoppingDemoApp3 extends App {

  val actorSystem = ActorSystem("LifecycleActorSystem")
  val lifecycleActor = actorSystem.actorOf(Props[LifecycleDemoLoggingActor], "lifecycleActor")

  lifecycleActor ! PoisonPill
}
{% endhighlight %}

*Kill*

Еще один вариант - вместо `PoisonPill` послать сообщение `Kill`.

{% highlight scala %}
object StoppingDemoApp4 extends App {

  val actorSystem = ActorSystem("LifecycleActorSystem")
  val lifecycleActor = actorSystem.actorOf(Props[LifecycleDemoLoggingActor], "lifecycleActor")

  lifecycleActor ! Kill
}
{% endhighlight %}

Разница между сообщениями `PoisonPill` или `Kill` в следующем:

* В случае `PoisonPill`, сообщение `Terminated` рассылается всем акторам, вызвавшим `context.watch` для этого актора.

* в ответ на сообщение `Kill`, актор бросает исключение `ActorKilledException`, что расценивается супервизором как отказ. Актор приостанавливается и здесь уже супервизор решает, как этот отказ обработать - продолжить выполнение, перезапустить актор или остановить его вообще. 

Вообще, процедура остановки актора учитывает древовидную структуру системы акторов, рассылая команду останова всем листьям и собирая их ответы для уже остановленного супервизора. 
При вызове `ActorSystem.terminate`, останавливается актор, называемый `system guardian`, роль которого именно в том, чтобы обеспечить правильную остановку всей системы.

Ну и поскольку остановка актора является асинхронной, нельзя, например, сразу воспользоваться именем актора, который был остановлен - это можно сделать только после того, как мы получим `Terminated` от него - для чего нужно будет опять-таки воспользоваться `context.watch`.


