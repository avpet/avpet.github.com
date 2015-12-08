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

Actors are stopped by invoking the stop method of a ActorRefFactory, i.e. ActorContext or ActorSystem. Typically the context is used for stopping the actor itself or child actors and the system for stopping top level actors. The actual termination of the actor is performed asynchronously, i.e. stop may return before the actor is stopped.

    class MyActor extends Actor {
     
      val child: ActorRef = ???
     
      def receive = {
        case "interrupt-child" =>
          context stop child
     
        case "done" =>
          context stop self
      }
     
    }

Processing of the current message, if any, will continue before the actor is stopped, but additional messages in the mailbox will not be processed. By default these messages are sent to the deadLetters of the ActorSystem, but that depends on the mailbox implementation.

Termination of an actor proceeds in two steps: first the actor suspends its mailbox processing and sends a stop command to all its children, then it keeps processing the internal termination notifications from its children until the last one is gone, finally terminating itself (invoking postStop, dumping mailbox, publishing Terminated on the DeathWatch, telling its supervisor). This procedure ensures that actor system sub-trees terminate in an orderly fashion, propagating the stop command to the leaves and collecting their confirmation back to the stopped supervisor. If one of the actors does not respond (i.e. processing a message for extended periods of time and therefore not receiving the stop command), this whole process will be stuck.

Upon ActorSystem.terminate, the system guardian actors will be stopped, and the aforementioned process will ensure proper termination of the whole system.




Принимающий актор обрабатывает сообщение – команду `SubscribeToTopic` – и высылает обратно ответное сообщение `Subscribed`. Итак, вторая версия `PublishSubscribeActor`'а (и теста).

Сначала - контракт сообщений `PublishSubscribeActor`'а:

{% highlight scala %}
object PublishSubscribeActor {
  case class SubscribeToTopic(topicName: String, subscriber: ActorRef)
  case class Subscribed(subscribe: SubscribeToTopic)
  case class SubscribedAlready(subscribe: SubscribeToTopic)

  case class GetTopicSubscribers(topic: String)
  case class Unsubscribe(topic: String, subscriber: ActorRef)
  case class Unsubscribed(unsubscribe: Unsubscribe)
  case class NotSubscribed(unsubscribe: Unsubscribe)

  case class PublishMessage(topic: String, message: Any)
  case class MessagePublished(publish: PublishMessage)

  final val ActorName = "publish-subscribe-actor"

  def props: Props = Props(new PublishSubscribeActor)
}
{% endhighlight %}

Ну а теперь - собственно поведение:

{% highlight scala %}
class PublishSubscribeActor extends Actor {
  import PublishSubscribeActor._

  private var subscribersMap = Map.empty[String, Set[ActorRef]].withDefaultValue(Set.empty)

  override def receive = {
    case subscribe @ SubscribeToTopic(topic, subscriber) =>
      subscribersMap += topic -> (subscribersMap(topic) + subscriber)
      sender() ! Subscribed(subscribe)

    case unsubscribe @ Unsubscribe(topic, subscriber) if !subscribersMap(topic).contains(subscriber) =>
      sender() ! NotSubscribed(unsubscribe)

    case unsubscribe @ Unsubscribe(topic, subscriber) =>
      subscribersMap += topic -> (subscribersMap(topic) - subscriber)
      sender() ! Unsubscribed(unsubscribe)

    case GetTopicSubscribers(topic) =>
      sender() ! subscribersMap(topic)

    case publish @ PublishMessage(topic, message) =>
      subscribersMap(topic).foreach(_ ! message)
      sender() ! MessagePublished(publish)

    case subscribe @ SubscribeToTopic(topic, subscriber) if subscribersMap(topic).contains(subscriber) =>
      sender() ! SubscribedAlready(subscribe)
  }
}
{% endhighlight %}

Как видно, поведение включает обработку команд – т.е. сообщений типа `PublishMessage` или `SubscribeToTopic` – и отсылку ответного сообщения обратно. Реакция актора на команду (например, `SubscribeToTopic`) определяется не только сообщением, но и текущим состоянием актора (в данном случае - поле `subscribersMap`).

Ну и нет нужды говорить о том, что, поскольку обрабатывается только одно сообщение за раз, то отпадает необходимость в синхронизации доступа к `subscribersMap`.

И наконец, несколько более расширенный тест:

{% highlight scala %}
val actor = system.actorOf(PublishSubscribeActor.props)

val subscriber1 = TestProbe()
val subscriber2 = TestProbe()
val subscriber3 = TestProbe()
val sender = TestProbe()
implicit val senderRef = sender.ref

val subscribe1 = SubscribeToTopic("topicOne", subscriber1.ref)
actor ! subscribe1
sender.expectMsg(Subscribed(subscribe1))

val subscribe2 = SubscribeToTopic("topicOne", subscriber2.ref)
actor ! subscribe2
sender.expectMsg(Subscribed(subscribe2))

val subscribe3 = SubscribeToTopic("topicTwo", subscriber3.ref)
actor ! subscribe3
sender.expectMsg(Subscribed(subscribe3))

actor ! GetTopicSubscribers("topicOne")
sender.expectMsg(Set(subscriber1.ref, subscriber2.ref))

actor ! subscribe1
sender.expectMsg(SubscribedAlready(subscribe1))

val message = "message"

val publish = PublishMessage("topicOne", message)
actor ! publish
sender.expectMsg(MessagePublished(publish))
subscriber1.expectMsg(message)
subscriber2.expectMsg(message)
subscriber3.expectNoMsg()
{% endhighlight %}

Взаимодействие "сообщение-ответное сообщение" с использованием операции `tell` 

{% highlight scala %}
val subscribe1 = SubscribeToTopic("topicOne", subscriber1.ref)
actor ! subscribe1
sender.expectMsg(Subscribed(subscribe1))
{% endhighlight %}

можно переписать в виде "запрос-ответ" с использованием оператора `?`, или `ask`. 

{% highlight scala %}
import akka.pattern.ask
val subscribe1 = SubscribeToTopic("topicOne", subscriber1.ref)
implicit val timeout = Timeout(5 seconds)
val future = actor ? subscribe1
val result = Await.result(future, timeout.duration).asInstanceOf[Subscribed]
result should be(Subscribed(subscribe1))
{% endhighlight %}

В этом случае в ответ мы получаем `Future`. Поскольку паттерн `ask` связан в равной как с акторами, так и с `Future`, то он оформлен не непосредственно как метод `ActorRef`, а добавляется имплицитной конвертацией из трейта [`AskSupport`](http://doc.akka.io/japi/akka/2.3.6/akka/pattern/AskSupport.html). Операция `ask` включает создание вспомогательного временного актора для обработки ответа, который будет уничтожен после определенного промежутка времени.

#### Основы жизненного цикла акторов  ####

В общем случае жизненный цикл актора сравнительно прост. Его можно сравнить, например, с жизненным циклом сервлета с некоторыми специфическими отличиями.

* Как и у любого класса, у актора есть конструктор;
* Следующим будет вызван метод `preStart`. В нем можно проинициализировать ресурсы, которые затем можно будет освободить в `postStop`;
* Между инициализацией актора и его остановкой, т.е. во все остальное время актор занимается обработкой сообщений в методе `receive`.

Например, простейший актор:

{% highlight scala %}
class LifecycleActor extends Actor with ActorLogging {

  log.info("LifecycleActor constructor")
  log.info(context.self.toString())

  override def preStart() = {
    log.info("preStart of LifecycleActor")
  }

  def receive = LoggingReceive {
    case "test_message" => log.info("test_message")
  }

  override def postStop() = {
    log.info("postStop of LifecycleActor")
  }

}

object LifecycleApp extends App {

  val actorSystem = ActorSystem("DemoSystem")
  val actor = actorSystem.actorOf(Props[LifecycleActor], "lifecycleActor")

  actor ! "test_message"

  // wait for a couple of seconds before shutdown
  Thread.sleep(2000)
  actorSystem.shutdown()
}

{% endhighlight %}

выводит:

    LifecycleActor constructor
    Actor[akka://DemoSystem/user/lifecycleActor#-1080888369]
    preStart of LifecycleActor
    test_message
    postStop of LifecycleActor

Фактически, разница между конструктором и `preStart`'ом не бросается в глаза. Даже в конструкторе актор имеет доступ к `ActorContext`, но, есть нюанс, например, при перезапуске актора, связанный с child-акторами. И конструктор, и `preStart` вызываются при перезапуске. Но фактически это два разных паттерна инициализации. Возможно, инициализация нужна для каждого нового поколения "воплощения" актора, но также возможен случай, когда инициализация нужна только в случае создания первого "воплощения" актора.

В случае инициализации с помощью конструктора мы имеем следующие преимущества. Во-первых, мы можем использовать `val` поля для того чтобы хранить состояние, которое не меняется за время жизни актора, т.е. мы повышаем иммутабельность актора. Конструктор вызывается для каждого воплощения актора, следовательно, реализация может всегда полагаться, что такая инициализация гарантированно произошла. Это также является недостатком этого метода, поскольку есть ситуации, когда какая-то реинициализация, наоборот, нежелательна при перезапуске. Например, часто полезно сохранять child-акторы. 

Именно в этом случае может использоваться `preStart()` актора  - он вызывается напрямую только при создании первого "воплощения" - то есть при создании `ActorRef`'а (который, естественно, не меняется при перезапуске актора). При перезапуске, `preStart` вызывается из `postRestart`, если последний не переопределен, при каждом перезапуске. Но мы можем переопределить `postRestart` и отключить таким образом подобное поведение, таким образом обеспечив единственный вызов `preStart`. 
