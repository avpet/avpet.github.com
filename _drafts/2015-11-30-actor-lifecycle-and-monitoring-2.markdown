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

Как видно, поведение включает обработку команд – т.е. сообщений типа `PublishMessage` или `SubscribeToTopic` – и отсылку ответного сообщения обратно. Whether a command is valid and yields a positive response – e.g. `Subscribed` – depends on both the command and the state, which is represented as the private mutable field subscribers.

As mentioned above, only one message is handled at a time and Akka makes sure that state changes are visible when the next message is processed, so there is no need to manually synchronize access to subscribers. Concurrency made easy!

Finally let’s take a look at a portion of the extended test:

{% highlight scala %}
val subscribe01 = Subscribe(topic01, subscriber01.ref)
mediator ! subscribe01
sender.expectMsg(Subscribed(subscribe01))
 
val subscribe02 = Subscribe(topic01, subscriber02.ref)
mediator ! subscribe02
sender.expectMsg(Subscribed(subscribe02))
 
val subscribe03 = Subscribe(topic02, subscriber03.ref)
mediator ! subscribe03
sender.expectMsg(Subscribed(subscribe03))
{% endhighlight %}

As you can see, we are sending Subscribe messages to the mediator using the ! operator and expect to receive respective responses. As before the full code of the current state can be accessed on GitHub under tag step-02.
