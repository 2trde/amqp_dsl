import pika
import json

import traceback
import os
import time

def log(str):
    print(time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime()) + ':  ' + str, flush = True)

class AmqpEndpoint:
    def __init__(self, exchange, request_topic, response_topic, on_receive, queue_name = None, amqp_connection = None, reconnect = True):
        '''
            Provides an amqp endpoint that listens to request incoming from
            exchange under request_topic and sends responses to
            the same exchange under response_topic.
            Incoming messages are handled by calling the function on_receive.
            You can start the service by calling .run().
            It is recommended to provide a queue_name (default is f'{exchange}.{topic}')
            as well as an amqp_connection (default is to attempt to read it from the environment).
            If you do not want the service to reconnect after the connection has
            been closed, set reconnect to False.
        '''
        if amqp_connection is None:
            amqp_connection = os.environ.get('AMQP_CONNECTION')
        if queue_name is None:
            queue_name = '.'.join([exchange, request_topic])
        
        self.parameters = pika.URLParameters(amqp_connection)
        self.connection = pika.BlockingConnection(self.parameters)
        self.channel = self.connection.channel()
        
        self.queue_name = queue_name
        self.channel.queue_declare(queue = queue_name, durable=True)
        self.channel.exchange_declare(exchange = exchange, exchange_type='topic')
        self.channel.queue_bind(queue_name, exchange, request_topic)
        self.exchange = exchange
        self.response_topic = response_topic
        
        self.reconnect = reconnect
        self.on_receive = on_receive
    
    def run(self):
        log('Service has been started, listening on queue {}.'.format(self.queue_name))
        try:
            for method_frame, _, body in self.channel.consume(self.queue_name):
                log('Received a new message.')
                self.channel.basic_ack(method_frame.delivery_tag)
                response = self.process_request(body)
                if response is not None:
                    # delivery_mode = 2 -> persistent
                    self.channel.basic_publish(self.exchange, self.response_topic, response, pika.BasicProperties(content_type='text/json', delivery_mode=2))
                    log('Sent response to exchange {}, topic {}.'.format(self.exchange, self.response_topic))
        except pika.exceptions.ConnectionClosed:
            if self.reconnect:
                log('The connection has been closed, reconnecting ...')
                self.connection = pika.BlockingConnection(self.parameters)
                self.channel = self.connection.channel()
                self.run()
            else:
                log('The connection has been closed, shutting down gracefully ...')
                channel.cancel()
                connection.close()
    
    def process_request(self, body):
        try:
            start_time = time.time()
            request = json.loads(body.decode('utf-8'))
            response = json.dumps(self.on_receive(request))
            elapsed_time = time.time() - start_time
            log('Successfully processed request, took {} seconds.'.format(elapsed_time))
            return response
        except Exception as error:
            log('Unexpected error: {}'.format(error))
            print(traceback.format_exc())
            log('Failed to process request.')
            return None
