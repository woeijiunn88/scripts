#!/bin/bash
sleep 100 >/tmp/test_fifo 2>&1 &
pid=$!
grep -v "foo" < /tmp/test_fifo &
fpid=$!
kill -TERM $pid
wait $pid
echo "Done wait pid"
wait $fpid
echo "Done wait fpid"
