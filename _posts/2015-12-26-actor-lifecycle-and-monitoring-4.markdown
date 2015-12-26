---
layout: post
title:  "Акторы и их жизненный цикл - IV"
date:   2015-12-26 20:30:00
categories: scala
image: http://i.imgur.com/pzn4gyb.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

### Тестирование жизненного цикла актора - [`ActorLifeCycleSpec`](https://github.com/akka/akka/blob/00f6a58e7c1e4795ad8920745c01916cc26947ca/akka-actor-tests/src/test/scala/akka/actor/ActorLifeCycleSpec.scala)  ###

Тесткейс [`ActorLifeCycleSpec`](https://github.com/akka/akka/blob/00f6a58e7c1e4795ad8920745c01916cc26947ca/akka-actor-tests/src/test/scala/akka/actor/ActorLifeCycleSpec.scala) содержит несколько тестов, описывающих жизненный цикл актора. Рассмотрим 1-й, тестирующий хуки на запуск и останов актора. Вообще тесткейс устроен следующим образом - в нем создаются актор-супервизор (`Supervisor`), и тестовый актор `LifeCycleTestActor`.  Супервизор устроен очень просто:

{% highlight scala %}
class Supervisor(override val supervisorStrategy: SupervisorStrategy) extends Actor {

  def receive = {
    case x: Props ⇒ sender() ! context.actorOf(x)
  }

  override def preRestart(cause: Throwable, msg: Option[Any]) {}
}
{% endhighlight %}

Т.е. для него будет переопределена `supervisorStrategy` - см. ниже; `preRestart` переопределен для того, чтобы предотвратить дефолтное поведение, которое заключается в том, что все child акторы останавливаются при перезапуске родителя. Все, что делает этот актор - принимает на вход конфигурационный объект `Props`, и возвращает child актор, с которым уже можно поэкспериментировать.

{% highlight scala %}
class LifeCycleTestActor(testActor: ActorRef, id: String, generationProvider: AtomicInteger) extends Actor {

  def report(msg: Any) = testActor ! message(msg)

  def message(msg: Any): Tuple3[Any, String, Int] = (msg, id, currentGen)

  val currentGen = generationProvider.getAndIncrement()

  override def preStart() { report("preStart") }

  override def postStop() { report("postStop") }

  def receive = { case "status" ⇒ sender() ! message("OK") }
}
{% endhighlight %}

`testActor` - это экземпляр специального актора `TestActor` из `TestKit`, который предназначен для верификации сообщений. id - уникальный идентификатор актора, и gen - так сказать, "номер поколения".  ’LifeCycleTestActor’ отправляет  сообщения `testActor`у, которые мы можем верифицировать в тесте. 

Вначале создается супервизор. Здесь стоит обратить внимание на параметр `maxNrOfRetries`. В некоторых случаях мы хотели бы сказать супервизору, чтобы он после нескольких перезапусков больше не пытался перезапустить актор:

{% highlight scala %}
val id = newUuid.toString
val supervisor = system.actorOf(Props(classOf[Supervisor], OneForOneStrategy(maxNrOfRetries = 3)(List(classOf[Exception]))))
{% endhighlight %}

Затем конфигурационный объект для child актора, который является экземпляром `LifeCycleTestActor`:

{% highlight scala %}
val gen = new AtomicInteger(0)
val restarterProps = Props(new LifeCycleTestActor(testActor, id, gen) {

  override def preRestart(reason: Throwable, message: Option[Any]) {
    report("preRestart")
  }

  override def postRestart(reason: Throwable) {
    report("postRestart")
  }
}).withDeploy(Deploy.local)
{% endhighlight %}

И наконец, сам актор создается с помощью супервизора:
{% highlight scala %}
val restarter = Await.result((supervisor ? restarterProps).mapTo[ActorRef], timeout.duration)
{% endhighlight %}

И первое же сообщение, которое мы получим, должно быть, разумеется, `"preStart"`:

{% highlight scala %}
expectMsg(("preStart", id, 0))
{% endhighlight %}

Теперь, мы отсылаем сообщение `Kill`, и у нас должна возникнуть новая "реинкарнация" актора:

{% highlight scala %}
restarter ! Kill
expectMsg(("preRestart", id, 0))
expectMsg(("postRestart", id, 1))
restarter ! "status"
expectMsg(("OK", id, 1))
{% endhighlight %}

То же самое происходит и второй, и третий раз. 
{% highlight scala %}
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
{% endhighlight %}

На четвертый же раз, поскольку мы указали `maxNrOfRetries` равным 3, то child актор `restarter` более не перезапустится.
{% highlight scala %}
restarter ! Kill
expectMsg(("postStop", id, 3))
expectNoMsg(1 seconds)
{% endhighlight %}


