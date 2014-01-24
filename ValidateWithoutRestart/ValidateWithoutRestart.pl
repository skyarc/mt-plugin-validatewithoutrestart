package MT::Plugin::ValidateWithoutRestart;
use strict;
use warnings;
use base 'MT::Plugin';

use File::Spec;

use MT::CMS::Plugin;
use MT::Util;
use MT::Touch2;

our $VERSION = '1.10';
our $NAME = ( split /::/, __PACKAGE__ )[-1];

my $plugin = __PACKAGE__->new(
    {   name        => $NAME,
        id          => lc $NAME,
        key         => lc $NAME,
        l10n_class  => $NAME . '::L10N',
        version     => $VERSION,
        author_name => 'SKYARC Co., Ltd.',
        author_link => 'http://www.skyarc.co.jp/',
        doc_link    => 'http://www.mtcms.jp/movabletype-blog/plugins/validatewithoutrestart/',
        description =>
            '<__trans phrase="Validate changing or modifing plugins without restarting web server when using FastCGI.">',
        registry => {
            applications => {
                cms => { methods => { redirect_meta => \&_redirect_meta, }, },
            },
        },
        init_request => \&_init_request,
    }
);
MT->add_plugin($plugin);

{
    my $orig = \&MT::CMS::Plugin::plugin_control;

    no warnings 'redefine';
    *MT::CMS::Plugin::plugin_control = sub {
        my ($app) = @_;
        $orig->($app);

        if ( $ENV{FAST_CGI} && !$app->{_errstr} && $app->{redirect} ) {
            MT::Touch2->touch( 0, 'config' );
            return _redirect_meta($app);
        }
    };
}

sub _redirect_meta {
    my ($app) = @_;

    my $redirect = $app->{redirect};
    $app->{redirect} = '';

    my $indicator = $app->static_path . '/images/ani-rebuild.gif';
    my $loading_msg
        = $plugin->translate('Now reconfiguring settings. Please wait ...');

    my $html = <<"HTMLHEREDOC";
<!DOCTYPE html>
<html>
    <head>
        <meta http-equiv="refresh"content="0.1;url=$redirect" />
    </head>
    <body>
        <img src="$indicator" />$loading_msg
    </body>
</html>
HTMLHEREDOC

    return $html;
}

sub _init_request {
    my ($app) = @_;

    _check_modified();

    my $touched = MT::Touch2->latest_touch( 0, 'config' );
    if ($touched) {
        $touched = MT::Util::ts2epoch( undef, $touched, 1 );

        my $startup = $app->{fcgi_startup_time};
        if ( $startup && $touched > $startup ) {
            my $mode = $app->param('__mode');
            $app->param( '__mode', 'redirect_meta' );

            my %param = %{ $app->{query}{param} };
            delete $param{__mode};

            my $redirect_uri = $app->uri(
                mode => $mode,
                args => \%param,
            );
            $app->redirect($redirect_uri);
        }
    }
}

sub _check_modified {
    my $touch_file = 'check_plugins_modified';
    my $touch_dir  = MT->config->TempDir;
    if ( !( -d $touch_dir ) ) {
        return;    # error
    }

    my $plugin_path = MT->config->PluginPath;
    if ( !( -d $plugin_path ) ) {
        return;    # error
    }

    my $cmd_check_removed = "find $plugin_path | wc -l";
    my $file_num          = `$cmd_check_removed`;

    my $touch_path = File::Spec->catfile( MT->config->TempDir, $touch_file );

    if ( -e $touch_path ) {
        my $cmd_check_modified = "find $plugin_path -newer $touch_path";
        my $ret                = `$cmd_check_modified`;

        open my $fh, '<', $touch_path;
        my $prev_file_num = readline $fh;
        close $fh;

        chomp $prev_file_num;

        if ( $file_num == $prev_file_num && !$ret ) {
            return;    # no change
        }
    }

    # some changes
    open my $fh, '>', $touch_path;
    print $fh $file_num;
    close $fh;

    MT::Touch2->touch( 0, 'config' );
}

1;
__END__
