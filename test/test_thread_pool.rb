require 'test/unit'

require 'puma/thread_pool'

class TestThreadPool < Test::Unit::TestCase

  def teardown
    @pool.shutdown if @pool
  end

  def new_pool(min, max, &blk)
    blk = proc { } unless blk
    @pool = Puma::ThreadPool.new(min, max, &blk)
  end

  def pause
    sleep 0.2
  end

  def test_append_spawns
    saw = []

    pool = new_pool(0, 1) do |work|
      saw << work
    end

    pool << 1

    pause

    assert_equal [1], saw
    assert_equal 1, pool.spawned
  end

  def test_append_queues_on_max
    finish = false
    pool = new_pool(0, 1) { Thread.pass until finish }

    pool << 1
    pool << 2
    pool << 3

    pause

    assert_equal 2, pool.backlog

    finish = true
  end

  def test_trim
    pool = new_pool(0, 1)

    pool << 1

    pause

    assert_equal 1, pool.spawned
    pool.trim

    pause
    assert_equal 0, pool.spawned
  end

  def test_trim_leaves_min
    finish = false
    pool = new_pool(1, 2) { Thread.pass until finish }

    pool << 1
    pool << 2

    finish = true

    assert_equal 2, pool.spawned
    pool.trim
    pause

    assert_equal 1, pool.spawned
    pool.trim
    pause

    assert_equal 1, pool.spawned

  end

  def test_trim_doesnt_overtrim
    finish = false
    pool = new_pool(1, 2) { Thread.pass until finish }

    pool << 1
    pool << 2

    assert_equal 2, pool.spawned
    pool.trim
    pool.trim

    finish = true

    pause

    assert_equal 1, pool.spawned
  end
end
