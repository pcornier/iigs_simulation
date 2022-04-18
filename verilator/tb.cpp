#include <fstream>
#include <getopt.h>
#include <verilated_vcd_c.h>
#include "Vtop__Syms.h"
#include "SDL2/SDL.h"
#include "SDL2/SDL_ttf.h"
#include <signal.h>
#include <string>
#include <iostream>
#include <regex>

#include <stdio.h>
#include <stdlib.h>
#include <readline/readline.h>
#include <readline/history.h>

Vtop* top;
bool running = true;
bool paused = false;

SDL_Window* window;
SDL_Surface* screen;
SDL_Surface* canvas;
int width = 640;
int height = 300;
bool dump_manual;

void sigHandler(int s) {
  if (paused) exit(0);
  paused = true;
}

void setPixel(SDL_Surface* dst, int x, int y, int color) {
  *((Uint32*)(dst->pixels) + x + y * dst->w) = color;
}


int main(int argc, char** argv, char** env) {

  int stop_arg = 10;
  int trace_arg = -1;
  int len_arg = 1;
  int dump_arg = -1;
  int import_arg = -1;
  int txtdmp = -1;
  int pauseAt = -1;
  int skip = 0;
  char *scr_arg = NULL;

  static struct option long_options[] = {
    {"trace", no_argument, 0, 't'},
    {"text", no_argument, 0, 'x'},
    {"stop", no_argument, 0, 's'},
    {"length", no_argument, 0, 'l'},
    {"dump", no_argument, 0, 'e'},
    {"import", no_argument, 0, 'i'},
    {"skip", no_argument, 0, 'k'},
    {"pauseat", no_argument, 0, 'p'},
    {"script", no_argument, 0, 'c'},
    {NULL, 0, NULL, 0}
  };

  int opt;
  while ((opt = getopt_long(argc, argv, "s:t:l:e:i:x:k:p:c:", long_options, NULL)) != -1) {
    switch (opt) {
      case 's':
        stop_arg = atoi(optarg);
        break;
      case 't':
        trace_arg = atoi(optarg);
        break;
      case 'l':
        len_arg = atoi(optarg);
        break;
      case 'c':
        scr_arg = optarg;
      case 'e':
        dump_arg = atoi(optarg);
        break;
      case 'i':
        import_arg = atoi(optarg);
        break;
      case 'x':
        txtdmp = atoi(optarg);
        break;
      case 'k':
        skip = atoi(optarg);
        break;
      case 'p':
        pauseAt = atoi(optarg);
        stop_arg = pauseAt + 10;
        break;
    }
  }

  int start_trace = trace_arg;
  int stop_trace  = trace_arg + len_arg;
  int stop_sim    = stop_arg;
  bool tracing = false;

  Verilated::commandArgs(argc, argv);

  window = SDL_CreateWindow(
    "sim",
    SDL_WINDOWPOS_UNDEFINED,
    SDL_WINDOWPOS_UNDEFINED,
    width, height,
    SDL_WINDOW_SHOWN
  );

  if (window == NULL) {
    printf("Could not create window: %s\n", SDL_GetError());
    return 1;
  }

  char title[55];

  screen = SDL_GetWindowSurface(window);
  canvas = SDL_CreateRGBSurfaceWithFormat(0, width, height, 24, SDL_PIXELFORMAT_RGB888);

  int hcycles = 0;
  uint64_t cycles = 0;
  top = new Vtop();
  top->reset = 1;

  Verilated::traceEverOn(true);
  VerilatedVcdC* tfp;
  if (start_trace != -1) {
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("dump.vcd");
  }

  int oldfetch = 0;
  int oldpc = 0;
  int oldbank = 0;

  std::ofstream ofile;
  if (txtdmp != -1) ofile.open("trace.txt");

  bool dirty;

  struct sigaction sigIntHandler;

  sigIntHandler.sa_handler = sigHandler;
  sigemptyset(&sigIntHandler.sa_mask);
  sigIntHandler.sa_flags = 0;

  sigaction(SIGINT, &sigIntHandler, NULL);

  std::ifstream scrfile;
  if (scr_arg != NULL) {
    scrfile.open(scr_arg);
    paused = true;
  }

  int oldh = -1;
  int hcount = 0;
  int vcount = 0;
  int hb, vb;

  int intkb, intfire, intadc, intctc;
  int ctc_io;

  while (running) {

    if (!paused) {

      if (cycles % 1'000'000 == 0 && pauseAt == hcycles+1) paused = true;

      if (start_trace >= 0 && hcycles >= start_trace) tracing = true;
      if (hcycles > stop_trace) tracing = false;
      if (tracing || dump_manual) tfp->dump((int)cycles);

      if (cycles % 1'000'000 == 0) hcycles++;
      if (hcycles > stop_sim) running = false;

      top->reset = cycles < 1'000'000;

      top->clk_sys = !top->clk_sys;
      top->clk_vid = top->clk_sys;
      top->ce_pix = 1;

      top->eval();

      int pc = top->top->core->cpu->ADDR_BUS & 0xffff;
      int bank =(top->top->core->cpu->ADDR_BUS >> 16) & 0xff;
      int fetch = top->top->core->cpu->VPA & top->top->core->cpu->VDA;
      if (fetch == 1 && txtdmp != -1 && hcycles >= txtdmp && oldfetch == 0 && pc != 0) {// && oldpc != pc) {
        if (oldpc != 0) {
          int A = top->top->core->cpu->A;
          int X = top->top->core->cpu->X;
          int Y = top->top->core->cpu->Y;
          char dbg[255];
          sprintf(dbg, "%02X/%04X: A=%04X X=%04X Y=%04X",  oldbank, oldpc, A, X, Y);
          ofile << dbg << std::endl;
        }
        oldpc = pc;
        oldbank = bank;
      }

      oldfetch = fetch;

      
      if (dirty) {

        SDL_BlitSurface(canvas, NULL, screen, NULL);
        SDL_UpdateWindowSurface(window);

        SDL_FillRect(canvas, NULL, 0x0);
        printf("refresh\n");
        dirty = false;
      }

      if (cycles % 4 == 0) {
        if (top->HS!= hb && !top->HS) {
          hcount = 0;
          vcount++;
        }
        else {
          hcount++;
        }

        if (top->VS != vb && !top->VS) {
          dirty = true;
          vcount = 0;
        }

        hb = top->HS;
        vb = top->VS;

        if (hcount >= 0 && hcount < width && vcount >= 0 && vcount < height) {
          int c = top->R << 16 | top->G << 8 | top->B ;
          setPixel(canvas, hcount, vcount, c);
        }

      }
      

      if (cycles % 1'000'000 == 0) {
        sprintf(title, "sim: %d/%d", (int)hcycles, stop_sim);
        SDL_SetWindowTitle(window, title);
        printf("sim: %d/%d %s\n", (int)hcycles-1, stop_sim, tracing||dump_manual ? "(tracing)" : "");
      }

      cycles++;

    }

    // paused

    else {

      printf("\rSimulation paused...\n");

      std::smatch sm;
      char* buf;

      while (paused) {

        std::string line;
        if (scrfile && std::getline(scrfile, line)) {
          buf = const_cast<char*>(line.c_str());
          printf(">> %s\n", buf);
        }
        else {
          buf = readline(">> ");
          if (strlen(buf) > 0) {
            add_history(buf);
          }
        }

        std::string command(buf);

        if (strcmp(buf, "run") == 0) paused = false;
        if (strcmp(buf, "exit") == 0) {
          running = false;
          paused = false;
        };

        if (std::regex_match(command, sm, std::regex("^run\\s+(\\d+).*"))) {
          int length = std::stoi(sm[1].str());
          pauseAt = hcycles+length;
          if (pauseAt >= stop_sim) stop_sim = pauseAt + 5;
          paused = false;
        }

        if (std::regex_match(command, sm, std::regex("^trace\\s+(\\d+).*"))) {
          int length = std::stoi(sm[1].str());
          if (length <= 10) {
            tfp = new VerilatedVcdC;
            top->trace(tfp, 99);
            tfp->open("dump.vcd");
            pauseAt = hcycles+length;
            if (pauseAt >= stop_sim) stop_sim = pauseAt + 5;
            paused = false;
            dump_manual = true;
          }
          else {
            printf("Big dump detected and cancelled, max length is 10!\n");
          }
        }

        if (command.compare("trace off") == 0) {
          tfp->close();
          dump_manual = false;
          printf("Tracing off\n");
        }

        if (std::regex_match(command, sm, std::regex("^pause\\s+(\\d+).*"))) {
          pauseAt = std::stoi(sm[1].str());
          if (pauseAt >= stop_sim) stop_sim = pauseAt + 5;
          printf("Will pause at %d\n", pauseAt);
          paused = false;
        }

        if (std::regex_match(command, sm, std::regex("^delay\\s+(\\d+).*"))) {
          int delay = std::stoi(sm[1].str());
          pauseAt = pauseAt + delay;
          if (pauseAt >= stop_sim) stop_sim = pauseAt + 5;
          printf("Will pause at %d\n", pauseAt);
          paused = false;
        }

      }

    }


  }

  // // print screen (40x24) at end of sim
   printf("-- dump --\n\n");
   int addr = 0x400;
   for (int s = 0; s < 3; s++) {
     addr = 0x400 + s*0x28;
     for (int r = 0; r < 8; r++) {
       printf("\t%04X:\t|", addr);
       for (int x=0; x<40;x++) {
         int c = top->top->__PVT__fastram__DOT__ram[addr+x]&0x7f;
         int c2 = top->top->__PVT__fastram__DOT__ram[addr+x];
         //printf("%c %x", c,c2);
         printf("%c", c);
       }
       addr += 128;
       printf("| seg %d\n", s);
     }
   }
   printf("\n\n");

  if (start_trace != -1) tfp->close();
  if (txtdmp != -1) ofile.close();

  return 0;
}
