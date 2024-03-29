//+------------------------------------------------------------------+
//|                                             Gradiente_Linear.mq5 |
//|                                                           Hidaii |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#property link "https://www.mql5.com"
#property copyright "Hidai"
#property version "1.02"
#property description "Exmeplo com gradiente linear"
//#property icon "logo03.ico"

#include <Trade\Trade.mqh>

CTrade trade;

// INPUTS
input group           "Principais"
input double lote = 1; // Quantidade de Lote
input double gain = 100; // Gain
input double loss = 250; // Loss
enum ENUM_TYPE_OPERATION {buy,  //Apenas Compra
                          sell, //Apenas Venda
                          both, //Ambos
                         };

input ENUM_TYPE_OPERATION enumTypeOperation = buy; //Tipo de operação
//Tamanho minimo para o Candle de sinal
int signalCandleSize = 0; //Candle de Sinal

input group           "Gradiente Linear"
// Total de parciais esperadas - pontos parciais - ordens pedentes
input int totalExpectedPartials = 3; //Quantidade de Parciais Esperadas
input double partialPoints = 50; //Pontos Parciais

//Magic
ulong magic = 123456; //Magic Number

double internal_gain = gain;
double internal_loss = loss;


//Candles rates = cotações
MqlRates rates[];

//BB tres buffers - armazernar valores da média
double upBand[];
double middleBand[];
double downBand[];

//Indicador
int handle;

//Para não repetir operações no mesmo candle
datetime lastOperatingCandle;

//Informar se teve uma operação
bool hadBuyOperation = false;
bool hadSellOperation = false;

//Primeira posição de venda aberta
double firstOpenSellPosition;

//Primeira posição de compra aberta
double firstOpenBuyPosition;



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---

//Verifica se as parciais comportam dento do loss principal
   if(!checkPartialLimit())
     {
      return(INIT_PARAMETERS_INCORRECT);
     }
//Configuração da banda - ativo, perido, deslocamento, desvio, aplicato em qual preço,
   handle = iBands(Symbol(),Period(),20,0,2.00,PRICE_CLOSE);
//                                                k d
   createMagicNumber();
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
//Inverte o array
   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(upBand, true);
   ArraySetAsSeries(middleBand, true);
   ArraySetAsSeries(downBand, true);

//Candles
   CopyRates(Symbol(),Period(),0,5,rates);

//Passa os valores do handle para as listas BB
   CopyBuffer(handle,0,0,5,middleBand);
   CopyBuffer(handle,1,0,5,upBand);
   CopyBuffer(handle,2,0,5,downBand);


   int buySign = (int)NormalizeDouble((rates[0].close - rates[0].open)/Point(),0); // candle de compra

   int sellSign = (int)NormalizeDouble((rates[0].open - rates[0].close)/Point(),0); //candle de venda

   if(OrdersTotal() == 0 && PositionsTotal() == 0)
     {
      for(int i=1; i<=totalExpectedPartials; i++)
        {
         removeDrawnLines("c"+i);
         removeDrawnLines("v"+i);
        }
     }

   if(hadSellOperation || hadBuyOperation) //Se não há uma posição aberta e foi realizada uma operação compra e/ou venda
     {
      //saveOrder();
      if(!statusBuyOperation() && hadBuyOperation)
        {
         if(closeBuyOrder())
           {
            for(int i=1; i<=totalExpectedPartials; i++)
              {
               removeDrawnLines("c"+i);  //TODO análisar a possibilidade de por uma variavel global
              }
            hadBuyOperation = false;
           }
        }
      if(!statusSellOperation() && hadSellOperation)
        {
         if(closeSellOrder())
           {
            for(int i=1; i<=totalExpectedPartials; i++)
              {
               removeDrawnLines("v"+i);
              }
            hadSellOperation = false;
           }
        }
     }

//verificação de posição de segurança
   if(statusBuyOperation() || statusSellOperation())
     {
      if(hadBuyOperation)
        {
         checkIfNeedcreateBuyOrders();
        }
      if(hadSellOperation)
        {
         checkIfNeedcreateSellOrders();
        }
     }

//Verifica se há operação em andamento - último candle
   if(lastOperatingCandle == rates[0].time)
     {
      return;
     }



//Rescrever as regras
//Regra atual... candle de sinal ... a minima/maxima está fora da banda e o fechando está dentro da banda...
//Complementos, candle de sinal [1] acima das linhas de baixa e média e candle a favor da venda
//se o fechamento do candle de entrada precisa se menor que o fechamento do candle de baixa(anterior) e/ou menor que a abertura do candle de alta(anteriro) rates[0].close < rates[1].close && rates[0].close < rates[1].open
   if(rates[1].high > upBand[1] && rates[1].close < upBand[1] && rates[1].open > downBand[1] && rates[0].close > middleBand[0])
     {
      ObjectCreate(0, rates[1].time+"_", OBJ_ARROW_STOP, 0, rates[1].time, rates[1].low);
      ObjectSetInteger(0, rates[0].time+"_",OBJPROP_COLOR,clrDeepPink);
     }
   if(rates[1].high > upBand[1] && rates[1].close < upBand[1] && rates[1].open > downBand[1] && sellSign >= signalCandleSize && rates[0].close > middleBand[0] && rates[0].close < rates[1].close && rates[0].close < rates[1].open)
     {
      string lpt = "sell_loss";
      if(true) //Verifica limite diario, está posicionado aqui para evitar execesso de reuisições no banco de dados E verificação se a última operação do dia houve loss desse tipo
        {
         if(!hadSellOperation && (enumTypeOperation == sell || enumTypeOperation == both))
           {
            double SL = SymbolInfoDouble(_Symbol,SYMBOL_ASK) + internal_loss; //loss
            double TP = SymbolInfoDouble(_Symbol,SYMBOL_ASK) - internal_gain; //gain
            if(trade.Sell(lote, Symbol(),0.00,0.00,0.00, NULL))
              {
               addTakeStop2();
               firstOpenSellPosition = getPositionPriceOpen("sell");
               checkIfNeedcreateSellOrders();

               lastOperatingCandle = rates[0].time;
               hadSellOperation = true;

              }
           }

        }

     }

   if(rates[1].low < downBand[1] && rates[1].close > downBand[1] && rates[1].open < upBand[1] && rates[0].close < middleBand[0])
     {
      ObjectCreate(0, rates[1].time+"_", OBJ_ARROW_CHECK, 0, rates[1].time, rates[1].low);
      ObjectSetInteger(0, rates[0].time+"_",OBJPROP_COLOR,clrLightGreen);
     }

   if(rates[1].low < downBand[1] && rates[1].close > downBand[1] && rates[1].open < upBand[1] && buySign >= signalCandleSize && rates[0].close < middleBand[0] && rates[0].close > rates[1].close && rates[0].close > rates[1].open)
     {
      string lpt = "buy_loss";
      if(true) //Verifica limite diario, está posicionado aqui para evitar execesso de reuisições no banco de dados E veirica se a última operação foi loss desse tipo
        {
         //if(lastPositionType != lpt)
         if(!hadBuyOperation && (enumTypeOperation == buy || enumTypeOperation == both))
           {
            double SL = SymbolInfoDouble(_Symbol,SYMBOL_ASK) - internal_loss; //loss
            double TP = SymbolInfoDouble(_Symbol,SYMBOL_ASK) + internal_gain; //gain
            if(trade.Buy(lote, Symbol(),0.00,0.00,0.00, NULL))
              {
               addTakeStop();
               firstOpenBuyPosition = getPositionPriceOpen("buy");
               checkIfNeedcreateBuyOrders();
               lastOperatingCandle = rates[0].time;
               hadBuyOperation = true;
              }
           }

        }

     }

  }
  
//+------------------------------------------------------------------+
//total expected orders
// TEO  OT  PT
// Se PT = OT + 1 >> todas as ordens abertas

//Se encostar no ponto a frente novamente reabre a ordem
//+------------------------------------------------------------------+
void createMagicNumber()
  {

   uchar arrayMagic[];
   StringToCharArray(_Symbol + "" + enumTypeOperation, arrayMagic);
   string stringMagic;
   for(int i=0; i<arrayMagic.Size(); i++)
     {
      stringMagic = stringMagic + (string)arrayMagic[i];
     }

   magic = StringToInteger(stringMagic);
   trade.SetExpertMagicNumber(magic);

  }


//+------------------------------------------------------------------+
//| Ordem pendente - Gradiente Linear                                |
//+------------------------------------------------------------------+
// Parametros: posição do preço principal, pontos parciais, status de ordem para analisar fechamento
void checkIfNeedcreateSellOrders()
  {

   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      //Print("Entrando no FOR addTakeStop");
      string symbol = PositionGetSymbol(i);
      //Print("Symbol ", symbol);
      if(symbol == Symbol() && PositionGetInteger(POSITION_MAGIC) == magic)   //Verifica se a ordem aberta é o ativo desejado E magic number
        {
         //Se a posição for comprada/vendido

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            if(OrdersTotal() + PositionsTotal() > 21)
              {
               Print("" + OrdersTotal() + PositionsTotal());
              }
            if(OrdersTotal() + PositionsTotal() != totalExpectedPartials + 1) // + 1 repersenta posicição inicial aberta
              {
               //Lista posições para comparação de existencia
               string listStrPositionPriceOpen = "";
               for(int i = PositionsTotal() -1; i >= 0; i--)
                 {
                  ulong ticketPosition = PositionGetTicket(i);
                  PositionSelectByTicket(ticketPosition);
                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                    {
                     double ppo = PositionGetDouble(POSITION_PRICE_OPEN);
                     listStrPositionPriceOpen = listStrPositionPriceOpen + ppo + ",";
                     //Print("Pos Ticket: " + ticketPosition + " >> Preço "+ ppo);
                    }


                 }
               //Lista ordens para comparação de existencia
               string listStrOrderPriceOpen = "";

               for(int i = OrdersTotal() -1; i >= 0; i--)
                 {
                  ulong ticketOrder = OrderGetTicket(i);

                  bool selected=OrderSelect(ticketOrder);
                  if(selected)
                    {
                     double opr = OrderGetDouble(ORDER_PRICE_OPEN);
                     if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL || OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
                       {
                        listStrOrderPriceOpen = listStrOrderPriceOpen + opr + ",";
                       }

                    }
                 }

               for(int i=1; i<=totalExpectedPartials; i++) // Ex 3 = abre 3 ordens inciando da posição menor
                 {

                  //                             entrada principal
                  double newPositionPartial = firstOpenSellPosition + partialPoints * i;
                  if(StringFind(listStrPositionPriceOpen + listStrOrderPriceOpen,""+newPositionPartial) == -1) //Se não houver posição ou ordem abre ou recria ordem
                    {
                     double takePartial = firstOpenSellPosition;
                     if(i != 1)
                       {
                        takePartial = NormalizeDouble(firstOpenSellPosition + partialPoints * (i -1), _Digits); // valor anterior
                       }
                     double newSLPartial = NormalizeDouble(firstOpenSellPosition + (internal_loss *_Point), _Digits);
                     trade.SellLimit(lote, newPositionPartial,Symbol(),newSLPartial,takePartial,ORDER_TIME_GTC,0,"parcial v " + i);
                     Print("Ordem venda pendente ", i, " aberta");
                     drawLine("v" + i, newPositionPartial, clrOrange);
                    }

                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void checkIfNeedcreateBuyOrders()
  {

   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      if(symbol == Symbol() && PositionGetInteger(POSITION_MAGIC) == magic)   //Verifica se a ordem aberta é o ativo desejado E magic number
        {
         //Se a posição for comprada/vendido
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            if(OrdersTotal() + PositionsTotal() != totalExpectedPartials + 1) // + 1 repersenta posicição inicial aberta
              {
               //Lista posições para comparação de existencia
               string listStrPositionPriceOpen = "";
               for(int i = PositionsTotal() -1; i >= 0; i--)
                 {
                  ulong ticketPosition = PositionGetTicket(i);
                  PositionSelectByTicket(ticketPosition);
                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    {
                     double ppo = PositionGetDouble(POSITION_PRICE_OPEN);
                     listStrPositionPriceOpen = listStrPositionPriceOpen + ppo + ",";
                    }
                 }
               //Lista ordens para comparação de existencia
               string listStrOrderPriceOpen = "";
               for(int i = OrdersTotal() -1; i >= 0; i--)
                 {
                  ulong ticketOrder = OrderGetTicket(i);
                  bool selected=OrderSelect(ticketOrder);
                  if(selected)
                    {
                     double opr = OrderGetDouble(ORDER_PRICE_OPEN);
                     if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY|| OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT)
                       {
                        listStrOrderPriceOpen = listStrOrderPriceOpen + opr + ",";
                       }

                    }
                 }

               for(int i=1; i<=totalExpectedPartials; i++)
                 {

                  //                             entrada principal
                  double newPositionPartial = firstOpenBuyPosition - partialPoints * i;
                  if(StringFind(listStrPositionPriceOpen + listStrOrderPriceOpen,""+newPositionPartial) == -1) //Se não houver posição ou ordem abre ou recria ordem
                    {
                     double takePartial = firstOpenBuyPosition;
                     if(i != 1)
                       {
                        takePartial = NormalizeDouble(firstOpenBuyPosition - partialPoints * (i -1), _Digits); // valor anterior
                       }
                     double newSLPartial = NormalizeDouble(firstOpenBuyPosition - (internal_loss *_Point), _Digits);
                     trade.BuyLimit(lote, newPositionPartial,Symbol(),newSLPartial,takePartial,ORDER_TIME_GTC,0,"parcial c" + i);
                     Print("Ordem compra pendente ", i, " aberta");
                     drawLine("c" + i, newPositionPartial, clrBlue);
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Take Ordem pendente                                              |
//+------------------------------------------------------------------+
void addTake()
  {

   uint total = PositionsTotal();

   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);

      if(symbol == Symbol())   //Verifica se a ordem aberta é o ativo desejado
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET); //Ticket da ordem
         double enterPrice = PositionGetDouble(POSITION_PRICE_OPEN); //Preço de abertura da ordem

         double newSL = 0.0;
         double newTP = 0.0;

         //Se a posição for comprada/vendido
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            newTP = NormalizeDouble(enterPrice + (internal_gain *_Point), _Digits);

            trade.PositionModify(ticket, newSL,newTP); //Add sl e tp
           }
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {

            double balance=AccountInfoDouble(ACCOUNT_BALANCE);
            newTP = NormalizeDouble(enterPrice - (internal_gain *_Point), _Digits);

            trade.PositionModify(ticket, newSL,newTP); //Add sl e tp
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Preço abetuta principal posição                                  |
//+------------------------------------------------------------------+
// enumTypeOperation = "buy, "sell"
double getPositionPriceOpen(string enumTypeOperation)
  {

//TODO LEVAR EM CONSIDERAÇÃO A POSSIBILIDADE DE PASSAR O VALOR PARA VARIAVES GLOBAIS EM CASO DE PRECISAR DE COMPRA E VENDA JUNTOS

   uint total = PositionsTotal();

   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);

      if(symbol == Symbol())   //Verifica se a ordem aberta é o ativo desejado
        {
         //Se a posição for comprada/vendido
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && enumTypeOperation == "buy")
           {

            return PositionGetDouble(POSITION_PRICE_OPEN); //Preço de abertura da ordem compra
           }
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && enumTypeOperation == "sell")
           {

            return PositionGetDouble(POSITION_PRICE_OPEN); //Preço de abertura da ordem venda
           }
        }
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Fecha a ordem em aberto                               |
//+------------------------------------------------------------------+
bool closeBuyOrder()
  {
   bool result = true;
   for(int i = OrdersTotal() -1; i >= 0; i--)
     {
      string symbol = OrderGetString(ORDER_SYMBOL);
      ulong magicNumber = OrderGetInteger(ORDER_MAGIC);
      if(symbol == Symbol() && magicNumber == magic)
        {
         if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY || OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT)
           {
            ulong ticketOrder = OrderGetTicket(i); //Ticket da ordem
            if(trade.OrderDelete(ticketOrder))
              {
               result = true;
              }
            else
              {
               return false;
              }
           }
        }
     }
   return result;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool closeSellOrder()
  {
   bool result = true;
   for(int i = OrdersTotal() -1; i >= 0; i--)
     {
      string symbol = OrderGetString(ORDER_SYMBOL);
      ulong magicNumber = OrderGetInteger(ORDER_MAGIC);
      if(symbol == Symbol() && magicNumber == magic)
        {
         if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL || OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
           {
            ulong ticketOrder = OrderGetTicket(i); //Ticket da ordem
            if(trade.OrderDelete(ticketOrder))
              {
               result = true;
              }
            else
              {
               return false;
              }
           }
        }
     }
   return result;
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool checkPartialLimit()
  {
   if(partialPoints * totalExpectedPartials <= internal_loss && totalExpectedPartials >= 0)
     {
      return true;
     }
   else
     {
      Alert("Quantidade de parciais X pontos parciais não comportam no loss ");
      return false;
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void drawLine(string id, double local, long colorObj)
  {
   ObjectCreate(0, id, OBJ_HLINE, 0, TimeCurrent(), local);
   ObjectSetInteger(0, id,OBJPROP_COLOR,colorObj);
   ObjectSetInteger(0, id,OBJPROP_STYLE,0,3);
   ObjectSetInteger(0, id,OBJPROP_BACK,false);

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void removeDrawnLines(string id)
  {
   ObjectDelete(0,id);

  }
//+------------------------------------------------------------------+
//| Fim Ordem pendente                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Take Stop                                                        |
//+------------------------------------------------------------------+
void addTakeStop()
  {
   uint total = PositionsTotal();

   for(int i = PositionsTotal() -1; i >= 0; i--)
     {

      string symbol = PositionGetSymbol(i);
      ulong magicNumber = PositionGetInteger(POSITION_MAGIC);

      if(symbol == Symbol() && magicNumber == magic)   //Verifica se a ordem aberta é o ativo desejado
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET); //Ticket da ordem
         double enterPrice = PositionGetDouble(POSITION_PRICE_OPEN); //Preço de abertura da ordem

         double newSL = 0.0;
         double newTP = 0.0;

         //Se a posição for comprada/vendido
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && enterPrice == firstOpenBuyPosition)
           {
            newSL = NormalizeDouble(enterPrice - (internal_loss *_Point), _Digits);
            newTP = NormalizeDouble(enterPrice + (internal_gain *_Point), _Digits);

            trade.PositionModify(ticket, newSL,newTP); //Add sl e tp
           }
        }
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void addTakeStop2()
  {
   uint total = PositionsTotal();

   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);

      ulong magicNumber = PositionGetInteger(POSITION_MAGIC);
      if(symbol == Symbol() && magicNumber == magic)   //Verifica se a ordem aberta é o ativo desejado
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET); //Ticket da ordem
         double enterPrice = PositionGetDouble(POSITION_PRICE_OPEN); //Preço de abertura da ordem

         double newSL = 0.0;
         double newTP = 0.0;

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL  && enterPrice == firstOpenSellPosition)
           {

            double balance=AccountInfoDouble(ACCOUNT_BALANCE);

            newSL = NormalizeDouble(enterPrice + (internal_loss *_Point), _Digits);
            newTP = NormalizeDouble(enterPrice - (internal_gain *_Point), _Digits);

            trade.PositionModify(ticket, newSL,newTP); //Add sl e tp
           }
        }
     }
  }


//Fechar operação
//+------------------------------------------------------------------+
//| Verificação TP SL por pontos - segunda verificação de segurança  |
//+------------------------------------------------------------------+
void checkTPSL()
  {

   double positionPriceOpen=PositionGetDouble(POSITION_PRICE_OPEN);
   double orderPriceOpen=OrderGetDouble(ORDER_PRICE_OPEN);

   int r = (int)NormalizeDouble((rates[0].close)/Point(),0);

   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      ulong magicNumber = PositionGetInteger(POSITION_MAGIC);
      if(symbol == Symbol() && magicNumber == magic)
        {
         int gainMore = internal_gain + (internal_gain * 0.1);
         int lossMore = internal_loss + (internal_loss * 0.1);

         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && (positionPriceOpen - rates[0].close) > gainMore || (rates[0].close - positionPriceOpen) >= lossMore)
           {
            closePosition();
            Alert("TAKE NÂO REALIZADO NA VENDA");
           }
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && (rates[0].close - positionPriceOpen) > gainMore || (positionPriceOpen - rates[0].close) >= lossMore)
           {
            closePosition();
            Alert("TAKE NÂO REALIZADO NA COMPRA");
           }
        }
     }

  }


//+------------------------------------------------------------------+
//| Verica se esta operando                                          |
//+------------------------------------------------------------------+
bool statusSellOperation()
  {
   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      ulong magicNumber = PositionGetInteger(POSITION_MAGIC);
      if(symbol == Symbol() && magicNumber == magic)
        {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && PositionGetDouble(POSITION_PRICE_OPEN) == firstOpenSellPosition)
           {
            CPositionInfo     m_positioninfo; //Verifica o uso dessa função para multiplos trades (Solução para contorno para aguarda o tempo de resposta do servidor)

            if(m_positioninfo.StopLoss() == 0 || m_positioninfo.TakeProfit() == 0)
              {
               Print("Não possui TP e SL, solicitando inserção");
               addTakeStop2();
              }

            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool statusBuyOperation()
  {
   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      ulong magicNumber = PositionGetInteger(POSITION_MAGIC);
      if(symbol == Symbol() && magicNumber == magic)
        {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && PositionGetDouble(POSITION_PRICE_OPEN) == firstOpenBuyPosition)
           {
            CPositionInfo     m_positioninfo; //Verifica o uso dessa função para multiplos trades (Solução para contorno para aguarda o tempo de resposta do servidor)

            if(m_positioninfo.StopLoss() == 0 || m_positioninfo.TakeProfit() == 0)
              {
               Print("Não possui TP e SL, solicitando inserção");
               addTakeStop();
              }

            return true;
           }
        }
     }
   return false;
  }



//+------------------------------------------------------------------+
//| Fecha a operação/posição em aberto                               |
//+------------------------------------------------------------------+
void closePosition()
  {
   for(int i = PositionsTotal() -1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      if(symbol == Symbol())
        {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY || PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            ulong ticket = PositionGetInteger(POSITION_TICKET); //Ticket da ordem
            trade.PositionClose(ticket,1);
           }
        }
     }
  }
//+------------------------------------------------------------------+
