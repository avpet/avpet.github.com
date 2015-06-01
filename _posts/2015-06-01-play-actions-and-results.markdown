---
layout: post
title:  "Play: Архитектура Action'ов"
date:   2015-06-01 15:30:00
categories: scala
image: http://i.imgur.com/jyNKm3u.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

Часть ядра фреймворка Play2, относящаяся собственно к обработке веб-запросов  - сравнительно небольшая, и основным типом в нем является `Action`, т.е. команда, и некоторое количество вспомогательных типов (`Request`, `Result`, `BodyParser` и др.).

В самом грубом приближении, ядро Play2 представляет собой API, которое занимается преобразованием вида:

{% highlight scala %}
RequestHeader -> Array[Byte] -> Result 
{% endhighlight %}

Приведенное [вычисление](https://www.haskell.org/arrows/) принимает на вход заголовок `RequestHeader`, затем принимает тело запроса как `Array[Byte]` и генерирует `Result`.

Этот тип предполагает вычитку всего тела запроса в память или на диск, а это не всегда хорошо с точки зрения расходования памяти.

В этом случае мы хотели бы получать тело запроса в виде блоков и обрабатывать их по мере поступления, если это необходимо.

Т.е. неплохо было бы поменять вторую стрелочку таким образом, она принимала на вход вот такие блоки и в конечном счете генерировала бы результат. И необходимый нам тип действительно существует, называется он `Iteratee`, и параметризуется двумя типами - тип входного параметра и тип результата.

Т.о., `Iteratee[E,R]` принимает на вход тип `E` и возвращает тип `R`, конкретно в данном случае - принимающий на вход `Array[Byte]`, возвращающий `Result`. Т.е. мы немного меняем тип вот так:

{% highlight scala %}
RequestHeader -> Iteratee[Array[Byte],Result]
{% endhighlight %}

Первую стрелочку мы просто заменяем на `Function[From,To]`, т.е. фактически заменяем стрелочку на символ `=>`:
`
{% highlight scala %}
RequestHeader => Iteratee[Array[Byte],Result]
{% endhighlight %}

Как мы знаем, для более выразительного построения новых типов с использованием уже существующих мы можем использовать инфиксные операторы типов. Если мы объявим псевдоним типа `Iteratee[E,R] `

{% highlight scala %}
type ==>[E,R] = Iteratee[E,R]
{% endhighlight %}

То теперь мы можем использовать его в качестве [инфиксного оператора типа](/scala/2015/05/31/scala-type-infix-operator.html#section-5):

{% highlight scala %}
RequestHeader => Array[Byte] ==> Result
{% endhighlight %}

Что означает следующее: на вход принимаем заголовки запроса, на вход же принимаем тело запроса в виде `Array[Byte]` и в финале возвращаем `Result`. Приблизительно таким образом объявлен трейт `EssentialAction`, который является базовым для всех команд (`action`ов)  (инфиксный оператора типов там не используется, мы привели его просто для наглядности):

{% highlight scala %}
trait EssentialAction extends (RequestHeader => Iteratee[Array[Byte], Result])
{% endhighlight %}

В то же время можно сказать, что тип `Result` является абстрактным представлением заголовков и тела ответа. В первом приближении такой тип выглядел бы вот так:

{% highlight scala %}
case class Result(headers: ResponseHeader, body:Array[Byte])
{% endhighlight %}

Но, опять же, как и в ситуации с запросом, мы бы хотели не сразу сформировать весь массив байт ответа (потому что он может быть довольно большим и занять всю память), а постепенно, блоками отдавать его клиенту. Поэтому нам неплохо было бы заменить `Array[Byte]` чем-то вроде генератора блоков байт.

Для этого у нас уже есть необходимый тип - `Enumerator[E]`, который может генерировать блоки типа `E`, в нашем случае - `Enumerator[Array[Byte]]`:

{% highlight scala %}
case class Result(headers:ResponseHeaders, body:Enumerator[Array[Byte]])
{% endhighlight %}

Если же нам все-таки не нужно отсылать ответ постепенно, а мы хотим отдать все тело ответа сразу, мы можем отослать все данные в одном блоке.

Любой тип данных `E`, который можно сконвертировать в поток байт, или `Array[Byte]`, может быть потенциально отдан в виде потока - за это отвечает объект типа `Writeable[E]`, который отдается в виде implicit'ного объекта, несколько упрощенно это можно представить как:

{% highlight scala %}
case class Result[E](headers:ResponseHeaders, body:Enumerator[E])(implicit writeable:Writeable[E])
{% endhighlight %}

На самом деле, правда, есть метода-фабрика в классе `Status` (`Status` и является `Result`ом), который создает результат.

{% highlight scala %}
def apply[C](content: C)(implicit writeable: Writeable[C]): Result
{% endhighlight %}

`EssentialAction` - всего лишь трейт, то есть интерфейс. В контроллерах реально будет использоваться производный от него `Action`, а точнее `Action[A]`. `Action[A]` наследуется от `EssentialAction`, при этом он уже может преобразовать типизированный `Request[A]`, а не просто поток байт, но для типа `A` должен быть предоставлен `BodyParser[A]`. 

{% highlight scala %}
trait Action[A] extends EssentialAction {

  type BODY_CONTENT = A

  def parser: BodyParser[A]

  def apply(request: Request[A]): Future[Result]

  //...
}
{% endhighlight %}

В силу асинхронной природы `Iteratee`, результатом `Action`'а уже является `Future[Result]` вместо `Result`. `Action`, вообще говоря тоже трейт, при реализации которого надо переопределить методы `apply` и `parser`.

Итак, мы установили, что (в подавляющем большинстве) запросы приложения, написанного с использованием *Play*, обрабатываются с помощью `Action`, который есть по сути функция `(play.api.mvc.Request => play.api.mvc.Result)`. Приведем пример простейшего `Action`а, т.е. "команды"

{% highlight scala %}
val echo = Action { request =>
  Ok("Got request [" + request + "]")
}
{% endhighlight %}

Тело `Action`'а возвращает значение `play.api.mvc.Result`, представляющее HTTP ответ, отсылаемый клиенту. В данном случае `Ok` вернет ответ со статусом `200 OK`, и типом тела ответа `text/plain`. Собственно, `Ok` - это константа

{% highlight scala %}
val Ok = new Status(OK)
{% endhighlight %}

Как мы уже говорили, фактически `Status` представляет собой вариант `Result`а:

{% highlight scala %}
class Status(status: Int) extends Result { // ...

    def apply[C](content: C)(implicit writeable: Writeable[C]): Result = ...
...
}
{% endhighlight %}

Вообще, надо заметить, что т.н. *companion-object* `Action` наследует `ActionBuilder[Request]`, в котором есть ряд методов-фабрик; в данном случае вызывается метод:

{% highlight scala %}
final def apply(block: R[AnyContent] => Result): Action[AnyContent] = apply(BodyParsers.parse.default)(block)
{% endhighlight %}

Т.е. используется `BodyParsers.parse.default`, который парсит тело запроса исходя из содержимого заголовка `"Content-Type"`. 

Вообще говоря, `BodyParser[A]` является на самом деле `Iteratee[Array[Byte],A]`, т.е. почти то же самое, что мы видели в `EssenatialAction`, за исключением того, что вместо `Result` здесь `A`.

Методы для создания разных видов команд (`Action`ов), как мы уже говорили, находятся в трейте `ActionBuilder`. Очевидно, что мы можем реализовать свой `ActionBuilder`, и использовать его для создания нужных нам видов команд. Например, пусть нам надо создать декоратор для логирования, т.е. фактически каждый вызов команды, созданной нами, будет логироваться.

Мы можем реализовать эту функциональность в методе `invokeBlock`, который вызывается для каждой команды, созданной `ActionBuilder`ом:

{% highlight scala %}
import play.api.mvc._

object LoggingAction extends ActionBuilder[Request] {
  def invokeBlock[A](request: Request[A], block: (Request[A]) => Future[Result]) = {
    Logger.info("Calling action")
    block(request)
  }
}
{% endhighlight %}

И теперь создадим логируемую команду:

{% highlight scala %}
def index = LoggingAction {
  Ok("Hello World")
}
{% endhighlight %}

#### Композиция команд ####

Иногда возникает необходимость в нескольких видах `ActionBuilder`'ов, например, если у нас разные виды аутентификации. Но в то же время мы не хотели бы отказываться от нашей логируемой команды, т.е. у нас возникает необходимость скомбинировать несколько `ActionBuilder`'ов.

Сделать это можно, например, вложением одной команды в другую, т.е. путем передачи некоторой команды `action` в наш логируемый вариант:

{% highlight scala %}
import play.api.mvc._

case class Logging[A](action: Action[A]) extends Action[A] {

  def apply(request: Request[A]): Future[Result] = {
    Logger.info("Calling action")
    action(request)
  }

  lazy val parser = action.parser
}
{% endhighlight %}

В принципе, то же самое можно сделать и без определения отдельного класса:

{% highlight scala %}
import play.api.mvc._

def logging[A](action: Action[A])= Action.async(action.parser) { request =>
  Logger.info("Calling action")
  action(request)
}
{% endhighlight %}

Есть еще в `ActionBuilder` такая вещь, как метод `composeAction`, специально созданный для этих целей:

{% highlight scala %}
object LoggingAction extends ActionBuilder[Request] {
  def invokeBlock[A](request: Request[A], block: (Request[A]) => Future[Result]) = {
    block(request)
  }
  override def composeAction[A](action: Action[A]) = new Logging(action)
}
{% endhighlight %}

После чего мы опять-таки можем просто вызвать LoggingAction:

{% highlight scala %}
def index = LoggingAction {
  Ok("Hello World")
}
{% endhighlight %}

Ну и конечно, подмешивание команд можно делать и без создания отдельного `ActionBuilder`а, просто вложением команд (правда, в этом случае мы теряем преимущества повторного использования, т.е. этот вариант годится, если, например, нам нужно залогировать только одну команду):

{% highlight scala %}
def index = Logging {
  Action {
    Ok("Hello World")
  }
}
{% endhighlight %}

