#!/usr/bin/env perl

use Test::More;
use Test::Exception;

use Paws;
use Paws::Kinesis::MemoryCaller;
use Paws::Credential::Explicit;
use Paws::Net::MultiplexCaller;

package Paws::Net::TestCaller {
  use Moose;
  with 'Paws::Net::CallerRole';
  use Test::More;
  has called_me_times => (
    is => 'ro',
    default => 0,
    traits => [ 'Counter' ],
    handles => {
      register_call => 'inc',
    }
  );
  sub do_call {
    my $self = shift;
    $self->register_call;
  }
  sub caller_to_response { }
}

my $paws1 = Paws->new(
  config => {
    credentials => Paws::Credential::Explicit->new(
      access_key => '-',
      secret_key => '-',
    ),
    caller => Paws::Net::MultiplexCaller->new(
      caller_for => {
        Kinesis => Paws::Kinesis::MemoryCaller->new(),
      },
      default_caller => Paws::Net::TestCaller->new 
    )
  }
);

use MIME::Base64 qw(encode_base64);
my $kinesis = $paws1->service('Kinesis', region => 'N/A');

# Shamelessly stolen from the Paws::Kinesis::MemoryCaller suite
# The objective of this test suite is to execute the same test suite,
# passing through the multiplexer, without the test suite noticing :)

my $existent_stream_name = "my_stream";
 
for my $shard_count (-1, 0) {
    throws_ok(
        sub {
            $kinesis->CreateStream(
                StreamName => "x", ShardCount => $shard_count,
            )
        },
        qr/ShardCount must be greater than zero to CreateStream/,
    );
}
 
$kinesis->CreateStream(StreamName => $existent_stream_name, ShardCount => 1);
 
throws_ok(
    sub { $kinesis->DescribeStream(StreamName => "x") },
    qr/StreamName\(x\) does not exist/,
);
 
my $describe_stream_output =
    $kinesis->DescribeStream(StreamName => $existent_stream_name);
 
my $existent_shard_id =
    $describe_stream_output->StreamDescription->Shards->[0]->ShardId;
ok $existent_shard_id, "Got a existent ShardId($existent_shard_id)";
 
throws_ok(
    sub {
        $kinesis->PutRecord(
            Data => "a",
            StreamName => $existent_stream_name,
            PartitionKey => 1,
        );
    },
    qr/Data\(a\) is not valid Base64/,
);
 
throws_ok(
    sub {
        $kinesis->PutRecord(
            Data => encode_base64("a"),
            StreamName => $existent_stream_name,
            PartitionKey => 1,
        );
    },
    qr/Data\([\w\=\n]+\) is not valid Base64/,
);
 
ok(
    $kinesis->PutRecord(
        Data => encode_base64("a", ""),
        StreamName => $existent_stream_name,
        PartitionKey => 1,
    ),
    'PutRecord successful with encode_base64 and EOL=""',
);
 
throws_ok(
    sub {
        $kinesis->PutRecord(
            Data => encode_base64("a", ""),
            StreamName => "x",
            PartitionKey => 1,
        );
    },
    qr/StreamName\(x\) does not exist/,
);
 
note "PutRecords";
 
throws_ok(
    sub {
        $kinesis->PutRecords(
            Records => [
                {
                    Data => 1,
                    PartitionKey => 1,
                }
            ],
            StreamName => $existent_stream_name,
        );
    },
    qr/Data\(1\) is not valid Base64/,
);
 
throws_ok(
    sub {
        $kinesis->PutRecords(
            Records => [
                {
                    Data => encode_base64(1, ""),
                    PartitionKey => 1,
                }
            ],
            StreamName => "x",
        );
    },
    qr/StreamName\(x\) does not exist/,
);
 
ok(
    $kinesis->PutRecords(
        Records => [
            {
                Data => encode_base64(1, ""),
                PartitionKey => 1,
            }
        ],
        StreamName => $existent_stream_name,
    ),
    "PutRecords was successful",
);
 
throws_ok(
    sub {
        $kinesis->GetShardIterator(
            ShardId => "y",
            ShardIteratorType => "b",
            StreamName => "x",
        );
    },
    qr/ShardIteratorType\(b\) is invalid or not implemented/,
);
 
throws_ok(
    sub {
        $kinesis->GetShardIterator(
            ShardId => "y",
            ShardIteratorType => "LATEST",
            StreamName => "x",
        );
    },
    qr/StreamName\(x\) does not exist/,
);
 
throws_ok(
    sub {
        $kinesis->GetShardIterator(
            ShardId => "y",
            ShardIteratorType => "LATEST",
            StreamName => $existent_stream_name,
        );
    },
    qr/ShardId\(y\) does not exist/,
);
 
my $get_shard_iterator_output = $kinesis->GetShardIterator(
    ShardId => $existent_shard_id,
    ShardIteratorType => "LATEST",
    StreamName => $existent_stream_name,
);
 
my $existent_shard_iterator = $get_shard_iterator_output->ShardIterator;
ok(
    $existent_shard_iterator,
    "Got an existent ShardIterator($existent_shard_iterator)",
);
 
throws_ok(
    sub { $kinesis->GetRecords(ShardIterator => 'abc') },
    qr/ShardIterator\(abc\) does not exist/,
);
 
ok(
    $kinesis->GetRecords(ShardIterator => $existent_shard_iterator),
    "GetRecords successful",
);

# End of the Kinesis test suite.

# Now we take a look if the default is working correctly

my $sqs = $paws1->service('SQS', region => 'test');
my $result = $sqs->CreateQueue(QueueName => 'qname');
cmp_ok($sqs->caller->default_caller->called_me_times, '==', 1, 'Called the default one time');

done_testing;
