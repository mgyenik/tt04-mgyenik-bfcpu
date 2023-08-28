import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles, First

def int2str(i):
    return bin(i)[2:].zfill(8)

def str2int(s):
    return int(s, 2)

async def read_bus(dut):
    dut.ui_in[0].value = 1
    t1 = Timer(2, units='us')
    await t1
    v = dut.uio_out.value
    dut.ui_in[0].value = 0
    return v.integer

async def run_program(dut, inp, program):
    program = bytes(program, 'utf-8')
    inp = bytes(inp, 'utf-8')
    out = []

    # Create linear memory cleared to 0
    mem = 30000*[0]
    addr = 0

    pidx = 0

    # Handle bus requests one at a time until we reach the end of the program.
    while True:
        # Wait for rdy
        rdy_edge = RisingEdge(dut.rdy)
        halt_edge = RisingEdge(dut.halted)
        edge = await First(rdy_edge, halt_edge)

        # If we halted, go ahead and return, otherwise it must have been rdy so
        # process the transaction
        if edge is halt_edge:
            break

        # Depending on mtype, handle request
        mtype = dut.mtype.value.binstr
        busctl = dut.busctl.value.binstr

        # read data
        if mtype == '000':
            if busctl == '00':
                b = await read_bus(dut)
                addr = addr & ~(0xff << 0)
                addr = addr | (b << 0)
            elif busctl == '01':
                b = await read_bus(dut)
                addr = addr & ~(0xff << 8)
                addr = addr | (b << 8)
            elif busctl == '10':
                b = await read_bus(dut)
                addr = addr & ~(0xff << 16)
                addr = addr | (b << 16)
            elif busctl == '11':
                dut.uio_in.value = int(mem[addr])

        # write data
        elif mtype == '001':
            if busctl == '00':
                b = await read_bus(dut)
                addr = addr & ~(0xff << 0)
                addr = addr | (b << 0)
            elif busctl == '01':
                b = await read_bus(dut)
                addr = addr & ~(0xff << 8)
                addr = addr | (b << 8)
            elif busctl == '10':
                b = await read_bus(dut)
                addr = addr & ~(0xff << 16)
                addr = addr | (b << 16)
            elif busctl == '11':
                mem[addr] = await read_bus(dut)

        # read char
        elif mtype == '010':
            b = inp[0]
            inp = inp[1:]
            dut.uio_in.value = b
        # write char
        elif mtype == '011':
            out.append(await read_bus(dut))
        # prog next
        elif mtype == '100':
            # if program[pidx] == 36:
            #     break
            dut.uio_in.value = int(program[pidx])
            pidx = pidx + 1
            assert pidx >= 0
        # prog prev
        elif mtype == '101':
            pidx = pidx - 1
            dut.uio_in.value = int(program[pidx])
            assert pidx >= 0

        dut.ack.value = 1

        # Deassert ack when rdy falls
        await FallingEdge(dut.rdy)
        dut.ack.value = 0

    # print(bytes(out).decode(encoding='utf-8', errors='strict'))
    output = bytes(out).decode(encoding='utf-8', errors='strict')
    return mem, output


async def do_reset(dut):
    dut._log.info("reset")
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1


class TestProgram(object):
    def __init__(self, name, prog, input_bytes='', expected_out=None, expected_mem=None):
        self.name = name
        self.prog = prog
        self.input_bytes = input_bytes
        self.expected_mem = expected_mem
        self.expected_out = expected_out

    def read_input(self):
        b = self.input_bytes[0]
        self.input_bytes = self.input_bytes[1:]
        return b

    def write_output(self, b):
        self.input_bytes = self.input_bytes[1:]
        return b

    async def run(self, dut):
        dut._log.info(f'running test {self.name}')
        await do_reset(dut)
        mem, output = await run_program(dut, self.input_bytes, self.prog)

        if len(output) != 0:
            dut._log.info('test output:')
            for line in output.splitlines():
                dut._log.info(f'    "{line}"')

        if self.expected_mem != None:
            # print('expected')
            # print(self.expected_mem)
            # print('actual')
            # print(mem[:len(self.expected_mem)])
            for i, v in enumerate(self.expected_mem):
                assert mem[i] == v

        if self.expected_out != None:
            assert output == self.expected_out


test_cases = [
    TestProgram(
        name = 'basic inc/dec',
        prog = '++++-->+<$',
        expected_mem = [2, 1, 0],
    ),
    TestProgram(
        name = 'basic loop',
        prog = '+++[>++<-]$',
        expected_mem = [0, 6, 0],
    ),
    TestProgram(
        name = 'xmas 7',
        prog = \
'''
>>>>>,>++<<<<<<>[-]>[-]>[-]>[-]>[<<<<+>>>>-]<<<<[>>>>>[
<<<<+>+>>>-]<<<[>>>+<<<-]<[>+<<-[>>[-]>+<<<-]>>>[<<<+>>
>-]<[<-[>>>-<<<[-]]+>-]<-]>>>+<<<<]>>>>>>+<<>>>+++++++[
>+++++<-]>---<<<<>>>+++++++[>>+++++<<-]<<<>>>++++++++++
<<<[->>>>>>+>+>>>>>>>>>+<<<<<<<<<<<<<<<<]>>[->>>>>>>+<<
<<<<<]>>>>+[>[->+>>>+>>+<<<<<<]>>[->+>>+<<<]>>[-<<<<<<<
.>>>>>>>]>[-<<<<<<<.>>>>>>>]>[-<<<<<<<<<.>>>>>>>>>]<<<<
<<<<<<.>>>>>>>>>><<<<<[-<+>]<->>>[-<+>]<++<<<-]>>>>>>>>
>>-[<<<<<<<<<<<<.>>>>>>>>>>>>-]<<<<<<<<<<<...$
''',
        input_bytes = '\x07',
        expected_out = \
'''   #   
  ###  
 ##### 
#######
  ###''',
    ),
    TestProgram(
        name = 'copy lines',
        prog = '+>>>>>>>>>>-[,+[-.----------[[-]>]<->]<]$',
        input_bytes = \
'''asdf 1
asdf 2
asdf 3
asdf 4
asdf 5
asdf 6
asdf 7
asdf 8
asdf 9
asdf 10
''',
        expected_out = \
'''asdf 1
asdf 2
asdf 3
asdf 4
asdf 5
asdf 6
asdf 7
asdf 8
asdf 9
asdf 10
''',
    ),
]


@cocotb.test()
async def test_bfcpu(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    for test in test_cases:
        await test.run(dut)
