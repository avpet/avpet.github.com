---
layout: post
title:  "Акторы и их жизненнный цикл - II"
date:   2015-12-02 00:30:00
categories: scala
image: http://i.imgur.com/pzn4gyb.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

#### Коммуникация: асинхронные сообщения  ####

Каждый актор по сути - это состояние и поведение, и коммуникация с акторами построена исключительно на обмене асинхронными сообщениями, которые помещаются в mailbox принимающего актора, и именно способность обрабатывать сообщения является его поведением.

Для того, чтобы послать сообщение актору, нам нужен его `ActorRef`:

{% highlight scala %}
publishSubscribeActor ! GetTopicSubscribers("topicName")
{% endhighlight %}

В классе `ActorRef` есть оператор `!` – или *"tell"* – с помощью которого сообщения отправляются соответсвующему актору. Как только сообщение отправлено, операция завершена и вызывающий код продолжает выполнение. Таким образом, здесь нет возвращаемого значения (кроме `Unit`), в этом и заключается асинхронность.

Этот способ является предпочтительным, поскольку в этом случае отсутствует блокирование на отправке, что конечно же, лучше, для паралелльности и как следствие - масштабируемости.

Если этот оператор вызван из другого актора, то имплицитно будет передана ссылка на актор-источник сообщения. Принимающий актор может получить эту ссылку (естественно, не на сам актор, а опять-таки `ActorRef`). Используя эту ссылку, принимающий актор может отправить ответное сообщение

{% highlight scala %}
sender() ! replyMsg
{% endhighlight %}

Если сообщение было отправлено не актором, то `sender` будет по умолчанию содержать ссылку на `deadLetters`.

{% highlight scala %}
override def receive = {
  case SubscribeToTopic(topicName) =>
    // ... process subscription ...
    sender() ! Subscribed
}
{% endhighlight %}

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

val subscribe1 = SubscribeToTopic("topicOne", subscriber1.ref)
actor ! subscribe1
sender.expectMsg(Subscribed(subscribe1))

val subscribe2 = SubscribeToTopic("topicTwo", subscriber2.ref)
actor ! subscribe2
sender.expectMsg(Subscribed(subscribe2))

val subscribe3 = SubscribeToTopic("topicThree", subscriber3.ref)
actor ! subscribe3
sender.expectMsg(Subscribed(subscribe3))

actor ! GetTopicSubscribers("topic1")
sender.expectMsg(Set(subscriber1.ref, subscriber2.ref))

actor ! subscribe1
sender.expectMsg(SubscribedAlready(subscribe1))

val message = "message"

val publish = PublishMessage("topic01", message)
actor ! publish
sender.expectMsg(MessagePublished(publish))
subscriber1.expectMsg(message)
subscriber2.expectMsg(message)
subscriber3.expectNoMsg()
{% endhighlight %}


