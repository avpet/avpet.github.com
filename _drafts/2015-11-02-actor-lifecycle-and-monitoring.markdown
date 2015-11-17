---
layout: post
title:  "Reactive Push, Composition и UI на примере Reactive Stocks - 2"
date:   2015-06-13 06:30:00
categories: scala
image: http://i.imgur.com/yHXn1A6.png
reactive-stock-src: https://github.com/typesafehub/reactive-stocks/blob/master/
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

### Жизненнный цикл и мониторинг акторов ###

#### Анатомия актора ####

Как показано на картинке ниже, актор состоит из нескольких взаимодействующих элементов. `ActorRef` представляет собой логический адрес актора и позволяет нам асинхронно посылать сообщения актору, т.е. не дожидаясь отклика. Dispatcher (диспетчер) – по умолчанию обычно есть 1 dispatcher на actor system – отвечает за постановку сообщений в очередь в mailbox'е актора, а также за scheduling извлечения сообщений из mailbox'а – причем только по одному за раз – для их последующей обработки в акторе. И наконец, актор, реализующий трейт Actor (собственно, это весь API, который мы должны реализовать) – инкапсулирует и состояние, и поведение.

{: .center}
![r5v1To1.png](http://i.imgur.com/r5v1To1.png)

Как мы увидим позднее, Akka не дает нам прямого доступа к Actor'у и таким образом обеспечивает то, что отправка асинхронных сообщений - единственный способ взаимодействия с актором: невозможно вызвать метод у актора. Также стоит заметить что отсылка сообщения актору и обработка этого сообщения актором - два совершенно разных действия, которые к тому же выполняются в разных потоках  – и разумеется, Akka обеспечивает всю необходимую синхронизацию  целью защиты состояния актора. Следовательно, Akka как бы создает иллюзию однопоточности, т.е. нам не нужно заботится о синхронизации доступа к разделяемой памяти.

#### Реализация актора ####

В Akka актор - класс, который реализует трейт `Actor`:

{% highlight scala %}
class MyActor extends Actor {
  override def receive = ???
}
{% endhighlight %}

Метод `receive` возвращает т.н. the so-called initial behavior of an actor. That’s simply a partial function used by Akka to handle messages sent to the actor. As the behavior is a PartialFunction[Any, Unit], there’s currently no way to define actors that only accept messages of a particular type. Actually there’s already an experimental module called akka-typed which brings back typesafety to Akka, but that’s not yet production-ready. By the way, an actor can change its behavior, which is the reason for calling the return value of the method receive the initial behavior.

UI приложения *Reactive Stocks* фактически состоит из одной страницы и устроен следующим образом. Схематично страница с котировками выглядит так:

{: .center}
![z1gezrZ.png](http://i.imgur.com/z1gezrZ.png)

Здесь верхняя панель (в приложении используется фреймворк [Bootstrap](http://getbootstrap.com/), в котором эта панель называется "*navbar*", т.е. навигационный заголовок) содержит только форму добавления новой котировки, которая состоит из двух контролов:

{: .center}
![qbwL0f0.png](http://i.imgur.com/qbwL0f0.png)

Остальная же часть страницы - один сплошной *<div>* `stocks`. При начальной загрузке кнопке *"Add stock"* назначается [обработчик]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L13)

{% highlight coffee %}
$("#addsymbolform").submit (event) ->
....
  ws.send(JSON.stringify({symbol: $("#addsymboltext").val()}))
....
{% endhighlight %}

который вызовет веб-сервис`/ws`, т.е. фактически метод [`controllers.Application.ws`]({{page.reactive-stock-src}}app/controllers/Application.java#L24), и будет передано JSON-сообщение вида `{symbol:<SYMBOL>}`, где `<SYMBOL>` - содержимое текстового контрола, т.е. название котировки. В ответ на запрос пользователя об отслеживании котировки, присылаемый через входной канал `WebSocket.In`, `WebSocket` из контроллера `Application` генерирует сообщение `WatchStock`, порождается цепочка сообщений, которая заканчивается JSON-сообщением `stockhistory`, отправляемым `UserActor`'ом в выходной канал `WebSocket`'а, и который содержит символ котировки и массив из 50 последних значений котировки. 

В ответ на это сообщение, вызовется [создание и заполнение 50-ю предыдущими значениями]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L7) нового графика с котировками. Схематично, реализация отображения графиков построено следующим образом (`stocks`, `flip-contaner` и остальные заголовки есть названия соотвествующих *<div>*ов):

{: .center}
![xxgEeK1.png](http://i.imgur.com/xxgEeK1.png)

Т.е. каждый график - это фактически *<div>* `chart-holder`, содержащий еще 2 *<div>'а* - собственно `chart` и `details-holder`. В свою очередь, *<div>* `chart-holder` вложен в *<div>* `flipper`,  а последний - *<div>* `flip-container`. `flip-container` нужен для следующей функциональности.   В приложении *Reactive Stocks*, если пользователь нажимает на график котировок, то он переворачивается, и далее должно быть отображено т.н. ["ожидание"](http://www.investopedia.com/terms/m/marketsentiment.asp) для данной котировки. Это самое ожидание образуется следующим образом - сначала делается поиск в твитере с упоминанием символа этой котировки, а затем делается запрос к специальному сервису, определяющему "настроение" переданного текста, на основании которого показывается картинка с ожиданием, т.е. рекомендация, что нужно делать - "buy", "sell" или "hold".

{: .center}
![ATYqE6S.png](http://i.imgur.com/ATYqE6S.png)

  Для того, чтобы по клику переворачивалась картинка и отображалась "рекомендация", [навешивается обработчик `handleFlip`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L47):

{% highlight coffee %}
populateStockHistory = (message) ->
....
  flipContainer = $("<div>").addClass("flip-container").append(flipper).click (event) ->
    handleFlip($(this))
....
{% endhighlight %}

Как уже отмечалось, есть две функции, обновляющие график, и обе отрабатывают в ответ на JSON-сообщения из входного (с точки зрения клиента) канала `WebSocket`'а:

* [`populateStockHistory`](https://github.com/typesafehub/reactive-stocks/blob/master/app/assets/javascripts/index.coffee#L7) - первоначальная, в ответ на JSON-сообщение `"stockhistory"`;
* [`updateStockChart`](https://github.com/typesafehub/reactive-stocks/blob/master/app/assets/javascripts/index.coffee#L9) - вызывается каждый раз в ответ на JSON-сообщение `"stockupdate"`; 

Для отрисовки используется библиотека [Flot](http://www.flotcharts.org/). Использовать ее очень просто - фактически, все, что нужно сделать - это вызвать функцию `plot`:

{% highlight coffee %}
$("#placeholder").plot(data, options)
{% endhighlight %}

где `placeholder` - это существующий DOM элемент, например, *<div>*, `data` - или [массив массивов (пар) координат, или спец. объекты](https://github.com/flot/flot/blob/master/API.md#data-format), ну и `options` - очевидно, что это такое - [объект со всякими настройками](https://github.com/flot/flot/blob/master/API.md#plot-options). 
Это, собственно, и делается, например, в [функции `populateStockHistory`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L50):

{% highlight coffee %}
chart.plot([getChartArray(message.history)], getChartOptions(message.history))
{% endhighlight %}

Задача функции [`updateStockChart`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L52) же лишь добавить одну координату в ответ на `"stockupdate"`, поэтому она извлекает данные из контрола

{% highlight coffee %}
plot = $("#" + message.symbol).data("plot")
{% endhighlight %}

добавляет к ним еще одну координату, вызывает [`plot.setData`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L58) и перерисовывает график.

#### Отрисовка ожидания ####

Как мы уже выяснили, при нажатии на график он должен перевернутся, и нам должна отобразиться одна из картинок - `buy`, `sell` или `hold`, и все это делается [в методе `handleFlip`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L69) Переворот осуществляется с помощью назначения спец. класса и CSS-трансформации, т.е. назначается класс `flipped`:

{% highlight coffee %}
container.addClass("flipped")
{% endhighlight %}

а этот класс описан в [main.less]({{page.reactive-stock-src}}app/assets/stylesheets/main.less#L30) с использованием трансформации, в данном случае - зеркального разворота 

{% highlight css %}
&.flipped .flipper {
  .transform(180deg);
}
{% endhighlight %}

Затем [делается ajax-запрос]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L77) к эндпойнту `/sentiment/<SYMBOL>`, где `<SYMBOL>`, как уже понятно - символ котировки (которой хранится в атрибуте `data-content` *<div>*а `flipper` и [соответственно извлекается оттуда]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L77)). И при успехе запроса, анализируется в JSON-ответе [анализируется поле `label`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L83) и в зависимости от возвращаемого значения - `pos`, `neg` или `neutral` - показывается соответствующее ожидание: `buy`, `sell` или `hold` . Для этого в *<div>* `details-holder` [устанавливается соответствующий текст и иконка]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L85), например:

{% highlight coffee %}
detailsHolder.append($("<h4>").text("The tweets say BUY!"))
detailsHolder.append($("<img>").attr("src", "/assets/images/buy.png"))
{% endhighlight %}

Но как именно определяется, какое именно ожидание показать?

### Реактивный запрос и реактивная композиция ###

Когда веб-сервер получает запрос, как правило, выделяется поток (например, из пула) для его обработки. В классической модели поток выделяется на все время обработки запроса вплоть до генерации ответа, даже в том случае, если обработка запроса потребует ожидания от другого, внешнего ресурса, например, веб-сервиса - и это может занять сравнительно большой промежуток времени. Реактивный же запрос с точки зрения клиента выглядит точно также, но внутри реализован таким образом, что реально 1 поток не блокируется на все время ожидания ответа от внешнего ресурса. Это означает, что если мы находимся в режиме ожидания ответа, т.е. поток активно не используется, он может использоваться для каких-нибудь других целей.
В приложении *Reactive Stocks* эндпойнт определения "настроения" котировки реализован именно с помощью реактивных запросов. Эндпойнт `/sentiment/<SYMBOL>` приводит к вызову в контроллере `StockSentiment` (см. [`conf/routes`]({{page.reactive-stock-src}}conf/routes#L7)):

{% highlight scala %}
GET /sentiment/:symbol controllers.StockSentiment.get(symbol)
{% endhighlight %}

Посмотрим на [сигнатуру этого метода]({{page.reactive-stock-src}}app/controllers/StockSentiment.scala#L59):

{% highlight scala %}
def get(symbol: String): Action[AnyContent] = Action.async {
{% endhighlight %}

Блок `async` говорит нам, что будет возвращен `Future[Result]`, т.е. обработка запроса происходит асинхронно. Внутри блока происходит приблизительно следующее:

1. Происходит вызов к прокси поиска на Твитере, находится некоторое количество твитов с упоминанием котировки
2. Для каждого твита определяется его "настроение"
3. Вычисляется значения "настроения"/"ожидания" для каждого твита
4. Вычисляются средние значения `neg`, `neutral` и `pos` для по вероятностям из предыдущего шага, и по ним определяется общее "настроение" котировки

Более детально: происходит вызов к прокси поиска на Твитере. Фактически это небольшое Scala-приложение [`twitter-search-proxy`](https://github.com/jamesward/twitter-search-proxy), клиент, который делает запросы к Twitter, кэширует их и обрабатывает отказы (которые случаются примерно в 10% случаев). В данном случае оно развернуто в облачном сервисе Heroku. [Возвращаемый JSON](twitter-search-proxy.herokuapp.com/search/tweets?q=GOOG) имеет примерно следующий вид:

{% highlight json %}
{
  "statuses": [
    {
      "metadata": {
        "iso_language_code": "en",
        "result_type": "recent"
      },
      "created_at": "Sun Jun 14 08:44:05 +0000 2015",
      "id": 610004771844562944,
      "text": "$BABA Cloud Services Will Be a Billion-Dollar Business By 2018... http://t.co/GX1v476Liy via @TheStreet #market #retail $GOOG $IBM $MSFT",
    }
  ],
  "search_metadata": {
    "completed_in": 0.054,
    "next_results": "?max_id=609998420472897535&q=GOOG&include_entities=1",
    "query": "GOOG",
    "count": 15
  }
}
{% endhighlight %}

где `statuses` - фактически отдельные найденные твиты. С помощью клиентской [библиотеки веб-сервисов Play](https://www.playframework.com/documentation/2.4.x/ScalaWS) делается [вызов к прокси поиска на Твитере](https://github.com/typesafehub/reactive-stocks/blob/master/app/controllers/StockSentiment.scala#L29):

{% highlight scala %}
WS.url(Play.current.configuration.getString("tweet.url").get.format(symbol)).get.withFilter { response =>
  response.status == OK
}
{% endhighlight %}

Для каждого твита определяется его "настроение". Это делается путем вызова к еще одному веб-сервису. На [http://text-processing.com/](http://text-processing.com/) есть ряд сервисов, связанных с обработкой текста, на интересует конкретно определение "настроения" - [http://text-processing.com/docs/index.html](http://text-processing.com/docs/index.html). Вызов делается [приблизительно аналогичным образом](https://github.com/typesafehub/reactive-stocks/blob/master/app/controllers/StockSentiment.scala#L19):

{% highlight scala %}
WS.url(Play.current.configuration.getString("sentiment.url").get) post Map("text" -> Seq(text))
{% endhighlight %}

[Затем подсчитывается]({{page.reactive-stock-src}}app/controllers/StockSentiment.scala#L36) средние значения `neg`, `neutral` и `pos` по вероятностям для "настроений"/"ожиданий", и [далее используется простой алгоритм]({{page.reactive-stock-src}}app/controllers/StockSentiment.scala#L48) для вычисления общего результата (который помещается в поле `label`). Если вероятность "нейтрального" "настроения" более 0.5, то результат будет "нейтральным". В ином случае, поскольку `neg` и `pos` в сумме дают 1, то берется тот, который из них больше.

{% highlight scala %}
if (neutral > 0.5)
  "neutral"
else if (neg > pos)
  "neg"
else
  "pos"
{% endhighlight %}

Все эти действия в сумме совершаются неблокирующим и асинхронным образом, т.е. являются реактивными, в том числе и запрос из браузера (поскольку ajax-запрос является тоже реактивным). Таким образом, вся цепочка запросов является реактивной, что является *реактивной композицией*:

{% highlight scala %}
Action.async {
  for {
    tweets <- getTweets(symbol) 
    futureSentiments = loadSentimentFromTweets(tweets.json)
    sentiments <- Future.sequence(futureSentiments) 
  } yield Ok(sentimentJson(sentiments))
}
{% endhighlight %}

