---
layout: post
title:  "Акторы и их жизненный цикл - III"
date:   2015-12-07 19:30:00
categories: scala
image: http://i.imgur.com/pzn4gyb.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

#### Остановка актора  ####

Актор может быть остановлен с помощью вызова метода `stop` из `ActorRefFactory`, т.е. `ActorContext` или `ActorSystem` - в зависимости от того, нужно ли актору остановить самого себя и child-акторы, или нужно остановить один из акторов верхнего уровня. Собственно остановка актора происходит асинхронно.

{% highlight scala %}
import akka.actor.{ActorRef, Actor}

class StoppingActor extends Actor {

  val child: ActorRef = ???

  def receive = {
    case "interrupt-child" =>
      context stop child

    case "done" =>
      context stop self
  }

}
{% endhighlight %}

Если в момент остановки обрабатывалось сообщение, оно будет обработано до конца, и только последующие сообщения уже не будут обрабатываться - по умолчанию, они отправятся специальному синтетическому актору `deadLetters`. 

Остановка актора происходит в два шага: сперва актор приостанавливает обработку сообщений из mailbox'а, а затем посылает сигнал остановки всем своим child-акторам, после этого обрабатывает внутренние нотификации остановки от child-акторов, и наконец, останавливается сам (при этом выхывается `postStop`, уничтожается mailbox, publishing Terminated on the DeathWatch, telling its supervisor). This procedure ensures that actor system sub-trees terminate in an orderly fashion, propagating the stop command to the leaves and collecting their confirmation back to the stopped supervisor. If one of the actors does not respond (i.e. processing a message for extended periods of time and therefore not receiving the stop command), this whole process will be stuck.

Upon ActorSystem.terminate, the system guardian actors will be stopped, and the aforementioned process will ensure proper termination of the whole system.

The postStop hook is invoked after an actor is fully stopped. This enables cleaning up of resources:

    override def postStop() {
      // clean up some resources ...
    }

Note

Since stopping an actor is asynchronous, you cannot immediately reuse the name of the child you just stopped; this will result in an InvalidActorNameException. Instead, watch the terminating actor and create its replacement in response to the Terminated message which will eventually arrive.
PoisonPill

You can also send an actor the akka.actor.PoisonPill message, which will stop the actor when the message is processed. PoisonPill is enqueued as ordinary messages and will be handled after messages that were already queued in the mailbox.
Graceful Stop

gracefulStop is useful if you need to wait for termination or compose ordered termination of several actors:

    import akka.pattern.gracefulStop
    import scala.concurrent.Await
     
    try {
      val stopped: Future[Boolean] = gracefulStop(actorRef, 5 seconds, Manager.Shutdown)
      Await.result(stopped, 6 seconds)
      // the actor has been stopped
    } catch {
      // the actor wasn't stopped within 5 seconds
      case e: akka.pattern.AskTimeoutException =>
    }

    object Manager {
      case object Shutdown
    }
     
    class Manager extends Actor {
      import Manager._
      val worker = context.watch(context.actorOf(Props[Cruncher], "worker"))
     
      def receive = {
        case "job" => worker ! "crunch"
        case Shutdown =>
          worker ! PoisonPill
          context become shuttingDown
      }
     
      def shuttingDown: Receive = {
        case "job" => sender() ! "service unavailable, shutting down"
        case Terminated(`worker`) =>
          context stop self
      }
    }

When gracefulStop() returns successfully, the actor’s postStop() hook will have been executed: there exists a happens-before edge between the end of postStop() and the return of gracefulStop().

In the above example a custom Manager.Shutdown message is sent to the target actor to initiate the process of stopping the actor. You can use PoisonPill for this, but then you have limited possibilities to perform interactions with other actors before stopping the target actor. Simple cleanup tasks can be handled in postStop.

Warning

Keep in mind that an actor stopping and its name being deregistered are separate events which happen asynchronously from each other. Therefore it may be that you will find the name still in use after gracefulStop() returned. In order to guarantee proper deregistration, only reuse names from within a supervisor you control and only in response to a Terminated message, i.e. not for top-level actors.


