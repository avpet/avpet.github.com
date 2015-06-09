---
layout: post
title:  "Reactive Push, Composition и UI на примере Reactive Stocks - 2"
date:   2015-06-09 05:30:00
categories: scala
image: http://i.imgur.com/yHXn1A6.png
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

Clicking on a stock chart will fetch recent news mentioning the stock symbol, use a service to do sentiment analysis on each news, and then display a buy, sell, or hold recommendation based on the aggregate sentiments. New stocks can be added to the list using the form in the header.
