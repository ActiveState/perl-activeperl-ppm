
sub ls_tree {
    my $dir = shift;
    my @res;
    require File::Find;
    File::Find::find({
       no_chdir => 1,
       wanted => sub {
           push(@res, $File::Find::name);
	   if (-f $_) {
	       push(@res, " ", -s _)
		   unless /\.db$/;
	   }
	   elsif (-d $_) {
	       push(@res, "/");
	   }
	   push(@res, "\n");
       },
       preprocess => sub {
	   return sort @_;
       }
    }, $dir);
    return join("", @res);
}

unless (caller) {
    print ls_tree(@ARGV);
}
