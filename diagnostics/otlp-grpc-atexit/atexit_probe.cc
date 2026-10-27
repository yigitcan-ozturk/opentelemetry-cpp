// The race needs one precondition: that gRPC threads are still running when the
// process starts executing atexit handlers, because OpenSSL's global cleanup is
// one of those handlers. That precondition does not need the crash to observe.
//
// Registering our handler first means OpenSSL's, registered later by gRPC's
// first use of it, runs BEFORE ours (atexit runs handlers in reverse order). So
// what this prints is the thread population at a point no earlier than
// OPENSSL_cleanup.
//
// argv: <mode>   0 = return from main   1 = std::_Exit

#include <grpcpp/grpcpp.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <memory>
#include <string>

namespace
{

void ReportThreads(const char *when)
{
  DIR *d = opendir("/proc/self/task");
  if (d == nullptr)
  {
    std::fprintf(stderr, "%s: cannot read /proc/self/task\n", when);
    return;
  }

  int count = 0;
  std::string names;
  for (dirent *e = readdir(d); e != nullptr; e = readdir(d))
  {
    if (e->d_name[0] == '.')
    {
      continue;
    }
    ++count;
    char path[128];
    std::snprintf(path, sizeof(path), "/proc/self/task/%s/comm", e->d_name);
    if (FILE *f = std::fopen(path, "r"))
    {
      char buf[64] = {0};
      if (std::fgets(buf, sizeof(buf), f) != nullptr)
      {
        buf[std::strcspn(buf, "\n")] = '\0';
        names += " ";
        names += buf;
      }
      std::fclose(f);
    }
  }
  closedir(d);
  std::fprintf(stderr, "%s: live threads = %d :%s\n", when, count, names.c_str());
}

void AtExitProbe()
{
  ReportThreads("ATEXIT (no earlier than OPENSSL_cleanup)");
}

}  // namespace

int main(int argc, char *argv[])
{
  const int mode = (argc > 1) ? std::atoi(argv[1]) : 0;

  // Registered before gRPC touches OpenSSL, so it runs after OpenSSL's own.
  std::atexit(AtExitProbe);

  grpc::SslCredentialsOptions ssl_opts;
  ssl_opts.pem_root_certs = "";
  grpc::ChannelArguments args;
  args.SetInt(GRPC_ARG_INITIAL_RECONNECT_BACKOFF_MS, 1);
  args.SetInt(GRPC_ARG_MIN_RECONNECT_BACKOFF_MS, 1);
  args.SetInt(GRPC_ARG_MAX_RECONNECT_BACKOFF_MS, 1);

  // Leaked, so that a live subchannel keeps retrying the failed handshake.
  auto *channel = new std::shared_ptr<grpc::Channel>(
      grpc::CreateCustomChannel("127.0.0.1:14317", grpc::SslCredentials(ssl_opts), args));
  (*channel)->GetState(true);
  (*channel)->WaitForStateChange(GRPC_CHANNEL_IDLE,
                                 std::chrono::system_clock::now() + std::chrono::milliseconds(300));

  ReportThreads("END OF MAIN                              ");

  std::fflush(nullptr);
  if (mode == 1)
  {
    std::_Exit(0);
  }
  return 0;
}
