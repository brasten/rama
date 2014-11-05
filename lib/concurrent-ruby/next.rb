# Cut-and-paste from https://github.com/pitr-ch/concurrent-ruby/tree/next
#

require 'concurrent'

module Concurrent

  # TODO Dereferencable
  # TODO document new global pool setting: no overflow, user has to buffer when there is too many tasks
  module Next


    # executors do not allocate the threads immediately so they can be constants
    # all thread pools are configured to never reject the job
    # TODO optional auto termination
    module Executors

      IMMEDIATE_EXECUTOR = ImmediateExecutor.new

      # Only non-blocking and short tasks can go into this pool, otherwise it can starve or deadlock
      FAST_EXECUTOR      = Concurrent::FixedThreadPool.new(
        [2, Concurrent.processor_count].max,
        idletime:  60, # 1 minute same as Java pool default
        max_queue: 0 # unlimited
      )

      # IO and blocking jobs should be executed on this pool
      IO_EXECUTOR        = Concurrent::ThreadPoolExecutor.new(
        min_threads: [2, Concurrent.processor_count].max,
        max_threads: Concurrent.processor_count * 100,
        idletime:    60, # 1 minute same as Java pool default
        max_queue:   0 # unlimited
      )

      def executor(which)
        case which
          when :immediate, :immediately
            IMMEDIATE_EXECUTOR
          when :fast
            FAST_EXECUTOR
          when :io
            IO_EXECUTOR
          when Executor
            which
          else
            raise TypeError
        end
      end
    end

    extend Executors

    module Shortcuts

      def post(executor = :fast, &job)
        Next.executor(executor).post &job
        self
      end

      # @return [Future]
      def future(executor = :fast, &block)
        Immediate.new(executor, &block).future
      end

      # @return [Delay]
      def delay(executor = :fast, &block)
        Delay.new(nil, executor, &block).future
      end

      alias_method :async, :future
    end

    extend Shortcuts

    begin
      require 'jruby'

      # roughly more than 2x faster
      class JavaSynchronizedObject
        def initialize
        end

        def synchronize
          JRuby.reference0(self).synchronized { yield }
        end

        def wait(timeout)
          if timeout
            JRuby.reference0(self).wait(timeout * 1000)
          else
            JRuby.reference0(self).wait
          end
        end

        def notify_all
          JRuby.reference0(self).notifyAll
        end
      end
    rescue LoadError
      # ignore
    end

    class RubySynchronizedObject
      def initialize
        @mutex     = Mutex.new
        @condition = Concurrent::Condition.new
      end

      def synchronize
        # if @mutex.owned?
        #   yield
        # else
        @mutex.synchronize { yield }
      rescue ThreadError
        yield
        # end
      end

      def wait(timeout)
        @condition.wait @mutex, timeout
      end

      def notify
        @condition.signal
      end

      def notify_all
        @condition.broadcast
      end
    end

    engine = defined?(RUBY_ENGINE) && RUBY_ENGINE
    case engine
      when 'jruby'
        class SynchronizedObject < JavaSynchronizedObject
        end
      when 'rbx'
        raise NotImplementedError # TODO
      else
        class SynchronizedObject < RubySynchronizedObject
        end
    end

    module FutureHelpers
      # fails on first error
      # does not block a thread
      # @return [Future]
      def join(*futures)
        countdown = Concurrent::AtomicFixnum.new futures.size
        promise   = ExternalPromise.new(futures)
        futures.each { |future| future.add_callback :join, countdown, promise, *futures }
        promise.future
      end
    end

    class Future < SynchronizedObject
      extend FutureHelpers
      extend Shortcuts

      singleton_class.send :alias_method, :dataflow, :join

      # @api private
      def initialize(promise, default_executor = :fast)
        super()
        synchronize do
          @promise          = promise
          @value            = nil
          @reason           = nil
          @state            = :pending
          @callbacks        = []
          @default_executor = default_executor
        end
      end

      # Has the obligation been success?
      # @return [Boolean]
      def success?
        state == :success
      end

      # Has the obligation been failed?
      # @return [Boolean]
      def failed?
        state == :failed
      end

      # Is obligation completion still pending?
      # @return [Boolean]
      def pending?
        state == :pending
      end

      alias_method :incomplete?, :pending?

      def completed?
        [:success, :failed].include? state
      end

      def promise
        synchronize { @promise }
      end

      # @return [Object] see Dereferenceable#deref
      def value(timeout = nil)
        wait timeout
        synchronize { @value }
      end

      # wait until Obligation is #complete?
      # @param [Numeric] timeout the maximum time in second to wait.
      # @return [Obligation] self
      def wait(timeout = nil)
        synchronize do
          touch
          # TODO interruptions ?
          super timeout if incomplete?
          self
        end
      end

      def touch
        promise.touch
      end

      # wait until Obligation is #complete?
      # @param [Numeric] timeout the maximum time in second to wait.
      # @return [Obligation] self
      # @raise [Exception] when #failed? it raises #reason
      def no_error!(timeout = nil)
        wait(timeout).tap { raise self if failed? }
      end

      # @raise [Exception] when #failed? it raises #reason
      # @return [Object] see Dereferenceable#deref
      def value!(timeout = nil)
        val = value(timeout)
        if failed?
          raise self
        else
          val
        end
      end

      def state
        synchronize { @state }
      end

      def reason
        synchronize { @reason }
      end

      def default_executor
        synchronize { @default_executor }
      end

      # @example allows Obligation to be risen
      #   failed_ivar = Ivar.new.fail
      #   raise failed_ivar
      def exception(*args)
        raise 'obligation is not failed' unless failed?
        reason.exception(*args)
      end

      # TODO needs better name
      def connect(executor = default_executor)
        ConnectedPromise.new(self, executor).future
      end

      # @yield [success, value, reason] of the parent
      def chain(executor = default_executor, &callback)
        add_callback :chain_callback, executor, promise = ExternalPromise.new([self], default_executor), callback
        promise.future
      end

      # @yield [value] executed only on parent success
      def then(executor = default_executor, &callback)
        add_callback :then_callback, executor, promise = ExternalPromise.new([self], default_executor), callback
        promise.future
      end

      # @yield [reason] executed only on parent failure
      def rescue(executor = default_executor, &callback)
        add_callback :rescue_callback, executor, promise = ExternalPromise.new([self], default_executor), callback
        promise.future
      end

      # lazy version of #chain
      def chain_delay(executor = default_executor, &callback)
        delay = Delay.new(self, executor) { callback_on_completion callback }
        delay.future
      end

      # lazy version of #then
      def then_delay(executor = default_executor, &callback)
        delay = Delay.new(self, executor) { conditioned_callback callback }
        delay.future
      end

      # lazy version of #rescue
      def rescue_delay(executor = default_executor, &callback)
        delay = Delay.new(self, executor) { callback_on_failure callback }
        delay.future
      end

      # @yield [success, value, reason] executed async on `executor` when completed
      # @return self
      def on_completion(executor = default_executor, &callback)
        add_callback :async_callback_on_completion, executor, callback
      end

      # @yield [value] executed async on `executor` when success
      # @return self
      def on_success(executor = default_executor, &callback)
        add_callback :async_callback_on_success, executor, callback
      end

      # @yield [reason] executed async on `executor` when failed?
      # @return self
      def on_failure(executor = default_executor, &callback)
        add_callback :async_callback_on_failure, executor, callback
      end

      # @yield [success, value, reason] executed sync when completed
      # @return self
      def on_completion!(&callback)
        add_callback :callback_on_completion, callback
      end

      # @yield [value] executed sync when success
      # @return self
      def on_success!(&callback)
        add_callback :callback_on_success, callback
      end

      # @yield [reason] executed sync when failed?
      # @return self
      def on_failure!(&callback)
        add_callback :callback_on_failure, callback
      end

      # @return [Array<Promise>]
      def blocks
        synchronize { @callbacks }.each_with_object([]) do |callback, promises|
          promises.push *callback.select { |v| v.is_a? Promise }
        end
      end

      def to_s
        "<##{self.class}:0x#{'%x' % (object_id << 1)} #{state}>"
      end

      def inspect
        "#{to_s[0..-2]} blocks:[#{blocks.map(&:to_s).join(', ')}]>"
      end

      # @api private
      def complete(success, value, reason, raise = true) # :nodoc:
        callbacks = synchronize do
          if completed?
            if raise
              raise MultipleAssignmentError.new('multiple assignment')
            else
              return nil
            end
          end
          if success
            @value = value
            @state = :success
          else
            @reason = reason
            @state  = :failed
          end
          notify_all
          @callbacks
        end

        callbacks.each { |method, *args| call_callback method, *args }
        callbacks.clear

        self
      end

      # @api private
      # just for inspection
      def callbacks
        synchronize { @callbacks }.clone.freeze
      end

      # @api private
      def add_callback(method, *args)
        synchronize do
          if completed?
            call_callback method, *args
          else
            @callbacks << [method, *args]
          end
        end
        self
      end

      private

      def set_promise_on_completion(promise)
        promise.complete success?, value, reason
      end

      def join(countdown, promise, *futures)
        if success?
          promise.success futures.map(&:value) if countdown.decrement.zero?
        else
          promise.try_fail reason
        end
      end

      def with_promise(promise, &block)
        promise.evaluate_to &block
      end

      def chain_callback(executor, promise, callback)
        with_async(executor) { with_promise(promise) { callback_on_completion callback } }
      end

      def then_callback(executor, promise, callback)
        with_async(executor) { with_promise(promise) { conditioned_callback callback } }
      end

      def rescue_callback(executor, promise, callback)
        with_async(executor) { with_promise(promise) { callback_on_failure callback } }
      end

      def with_async(executor)
        Next.executor(executor).post { yield }
      end

      def async_callback_on_completion(executor, callback)
        with_async(executor) { callback_on_completion callback }
      end

      def async_callback_on_success(executor, callback)
        with_async(executor) { callback_on_success callback }
      end

      def async_callback_on_failure(executor, callback)
        with_async(executor) { callback_on_failure callback }
      end

      def callback_on_completion(callback)
        callback.call success?, value, reason
      end

      def callback_on_success(callback)
        callback.call value if success?
      end

      def callback_on_failure(callback)
        callback.call reason if failed?
      end

      def conditioned_callback(callback)
        self.success? ? callback.call(value) : raise(reason)
      end

      def call_callback(method, *args)
        self.send method, *args
      end
    end

    class Promise < SynchronizedObject
      # @api private
      def initialize(executor = :fast)
        super()
        future = Future.new(self, executor)

        synchronize do
          @future     = future
          @blocked_by = []
          @touched    = false
        end
      end

      def future
        synchronize { @future }
      end

      def blocked_by
        synchronize { @blocked_by }
      end

      def state
        future.state
      end

      def touch
        blocked_by.each(&:touch) if synchronize { @touched ? false : (@touched = true) }
      end

      def to_s
        "<##{self.class}:0x#{'%x' % (object_id << 1)} #{state}>"
      end

      def inspect
        "#{to_s[0..-2]} blocked_by:[#{synchronize { @blocked_by }.map(&:to_s).join(', ')}]>"
      end

      private

      def add_blocked_by(*futures)
        synchronize { @blocked_by += futures }
        self
      end

      def complete(success, value, reason, raise = true)
        future.complete(success, value, reason, raise)
        synchronize { @blocked_by.clear }
      end

      # @return [Future]
      def evaluate_to(&block) # TODO for parent
        complete true, block.call, nil
      rescue => error
        complete false, nil, error
      end
    end

    class ExternalPromise < Promise
      def initialize(blocked_by_futures, executor = :fast)
        super executor
        add_blocked_by *blocked_by_futures
      end

      # Set the `IVar` to a value and wake or notify all threads waiting on it.
      #
      # @param [Object] value the value to store in the `IVar`
      # @raise [Concurrent::MultipleAssignmentError] if the `IVar` has already been set or otherwise completed
      # @return [Future]
      def success(value)
        complete(true, value, nil)
      end

      def try_success(value)
        complete(true, value, nil, false)
      end

      # Set the `IVar` to failed due to some error and wake or notify all threads waiting on it.
      #
      # @param [Object] reason for the failure
      # @raise [Concurrent::MultipleAssignmentError] if the `IVar` has already been set or otherwise completed
      # @return [Future]
      def fail(reason = StandardError.new)
        complete(false, nil, reason)
      end

      def try_fail(reason = StandardError.new)
        !!complete(false, nil, reason, false)
      end

      public :evaluate_to

      # @return [Future]
      def evaluate_to!(&block)
        evaluate_to(&block).no_error!
      end
    end

    class ConnectedPromise < Promise
      def initialize(future, executor = :fast)
        super(executor)
        connect_to future
      end

      # @api private
      public :complete

      private

      # @return [Future]
      def connect_to(future)
        add_blocked_by future
        future.add_callback :set_promise_on_completion, self
        self.future
      end
    end

    class Immediate < Promise
      def initialize(executor = :fast, &task)
        super(executor)
        Next.executor(executor).post { evaluate_to &task }
      end
    end

    class Delay < Promise
      def initialize(blocked_by_future, executor = :fast, &task)
        super(executor)
        synchronize do
          @task      = task
          @computing = false
        end
        add_blocked_by blocked_by_future if blocked_by_future
      end

      def touch
        if blocked_by.all?(&:completed?)
          execute_once
        else
          blocked_by.each { |f| f.on_success! { self.touch } unless synchronize { @touched } }
          super
        end
      end

      private

      def execute_once
        execute, task = synchronize do
          [(@computing = true unless @computing), @task]
        end

        if execute
          Next.executor(future.default_executor).post { evaluate_to &task }
        end
        self
      end
    end

  end
end