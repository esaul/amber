(%
 % rowl - generation 1
 % Copyright (C) 2010 nineties
 %
 % $Id: tcodegen.rl 2010-03-26 16:37:18 nineties $
 %);

(% translate typed rowlcore to Three-address Code %);

include(stddef, code);
export(tcodegen, mkinst);

vtable: NULL; (% variable table. variable id to corresponding operand %);

(% p0: identifier, p1: operand %);
set_operand: (p0, p1) {
    allocate(1);
    x0 = p0[3]; (% identifier-id %);
    assert(x0 < vec_size(vtable));
    vec_put(vtable, x0, p1);
};

(% p0: identifier %);
get_operand: (p0) {
    allocate(2);
    x0 = p0[3]; (% identifier-id %);
    assert(x0 < vec_size(vtable));
    x1 = vec_at(vtable, x0);
    assert(x1 != NULL);
    return x1;
};

(% p0: opcode, p1: output reg, p2: intput reg%);
mkinst: (p0, p1, p2) {
    return mktup6(TCODE_INST, p0, p1, p2, mkiset(), 0);
};

LABEL_BUF_SIZE => 128;
labelbuf : char [LABEL_BUF_SIZE];
label_id : 0;
labelbuf_idx : 0;

reset_labelbuf: () {
    labelbuf_idx = 0;
    wch(labelbuf, 0, '\0');
};

put_labelchar: (p0) {
    if (labelbuf_idx >= LABEL_BUF_SIZE-1) {
	fputs(stderr, "ERROR: too long label name");
	fputs(stderr, labelbuf);
	fputs(stderr, "...\n");
	exit(1);
    };
    wch(labelbuf, labelbuf_idx, p0);
    labelbuf_idx = labelbuf_idx + 1;
    wch(labelbuf, labelbuf_idx, '\0');
};

put_labelstr: (p0) {
    while (rch(p0, 0) != '\0') {
	put_labelchar(rch(p0, 0));
	p0 = p0 + 1;
    };
};

labelint_digits: char [10]; (% 32bit decimal integers are less than 11 digits %);
put_labelint: (p0, p1) {
    allocate(1);

    wch(labelint_digits, 0, p1%10 + '0');
    p1 = p1/10;
    x0 = 0;
    while (p1 != 0) {
        x0 = x0 + 1;
        wch(labelint_digits, x0, p1%10 + '0');
        p1 = p1/10;
    };

    while (x0 >= 0) {
	put_labelchar(rch(labelint_digits, x0));
        x0 = x0 - 1;
    };
};

new_label: () {
    reset_labelbuf();
    put_labelstr("L.");
    put_labelint(label_id);
    label_id = label_id + 1;
    return strdup(labelbuf);
};

topdecl : NULL;
add_topdecl: (p0) {
    topdecl = ls_cons(p0, topdecl);
};

not_reachable: (p0) {
    fputs(stderr, "ERROR: not reachable here\n");
    exit(1);
};

not_implemented: (p0) {
    fputs(stderr, "ERROR: not implemented\n");
    exit(1);
};

transl_funcs: [
    not_reachable, not_implemented, transl_integer, transl_string, transl_identifier,
    not_implemented, transl_code, not_implemented, not_implemented, transl_call,
    not_implemented, not_implemented, not_implemented, transl_binexpr, not_implemented,
    not_implemented, transl_ret, transl_retval, transl_syscall
];

transl_integer: (p0, p1, p2) {
    allocate(1);
    x0 = p1[1]; (% type %);
    if (x0[0] == NODE_CHAR_T) {
        *p2 = mktup2(OPD_CHAR, p1[3]);
        return p0;
    };
    if (x0[0] == NODE_INT_T) {
        *p2 = mktup2(OPD_INTEGER, p1[3]);
        return p0;
    };
    not_reachable();
};

transl_string: (p0, p1, p2) {
    allocate(1);
    x0 = new_label();
    add_topdecl(mktup4(TCODE_DATA, x0, mktup2(DATA_STRING, p1[2]), FALSE));
    *p2 = mktup2(OPD_ADDRESS, x0);
    return p0;
};

transl_identifier: (p0, p1, p2) {
    allocate(1);
    *p2 = get_operand(p1);
    return p0;
};

(% p1: argument %);
set_arguments: (p0, p1) {
    allocate(5);
    x0 = p1[TUPLE_LENGTH];
    x1 = p1[TUPLE_ELEMENTS];
    x2 = 0;
    x3 = NULL;
    while (x2 < x0) {
        p0 = transl_item(p0, x1[x2], &x4);
        x3 = ls_cons(mkinst(INST_MOVL, get_stack(x2), x4), x3);
        x2 = x2 + 1;
    };
    return ls_append(x3, p0);
};

transl_call: (p0, p1, p2) {
    allocate(4);
    x0 = p1[2]; (% function %);
    x1 = p1[3]; (% argument %);
    if (x0[0] == NODE_IDENTIFIER) {
        x2 = mangle(x0[1], get_ident_name(x0));

        p0 = set_arguments(p0, x1);
        p0 = ls_cons(mkinst(INST_CALL_IMM, NULL, mktup2(OPD_LABEL, x2)), p0);

        x3 = create_pseudo();
        p0 = ls_cons(mkinst(INST_MOVL, x3, get_eax()), p0);
        *p2 = x3;
        return p0;
    };
    p0 = transl_item(p0, x0, &x2);
    p0 = set_arguments(p0, x1);
    p0 = ls_cons(mkinst(INST_CALL_IND, NULL, x2), p0);
    x3 = create_pseudo();
    p0 = ls_cons(mkinst(INST_MOVL, x3, get_eax()), p0);
    *p2 = x3;
    return p0;
};

bininst: [0, INST_ADDL, INST_SUBL];

transl_binexpr: (p0, p1, p2) {
    allocate(3);
    (% t = x op y
     %
     % <->
     %
     % t = x;
     % t op= y;
     %);
    p0 = transl_item(p0, p1[3], &x0);
    p0 = transl_item(p0, p1[4], &x1);
    x2 = create_pseudo();
    *p2 = x2;
    p0 = ls_cons(mkinst(INST_MOVL, x2, x0), p0);
    p0 = ls_cons(mkinst(bininst[p1[2]], x2, x1), p0);
    return p0;
};

(% p0: output tcode, p1: code block %);
transl_code: (p0, p1, p2) {
    allocate(3);
    x0 = p1[2];
    x1 = NULL;
    while (x0 != NULL) {
        p0 = transl_item(p0, ls_value(x0), &x2);
        x0 = ls_next(x0);
    };
    return p0;
};

transl_ret: (p0, p1, p2) {
    return ls_cons(mkinst(INST_RET, NULL, NULL), p0);
};

transl_retval: (p0, p1, p2) {
    allocate(2);
    p0 = transl_item(p0, p1[2], &x0);
    p0 = ls_cons(mkinst(INST_MOVL, get_physical_reg(0), x0), p0);
    x1 = mkinst(INST_RET, NULL, NULL);
    x1[INST_ARG] = TRUE;
    return ls_cons(x1, p0);
};

transl_syscall: (p0, p1, p2) {
    allocate(7);
    x0 = p1[2]; (% argument tuple %);
    x1 = x0[TUPLE_LENGTH];
    x2 = x0[TUPLE_ELEMENTS];
    x3 = memalloc(4*x1); (% translated operands %);
    x4 = 0;

    while (x4 < x1) {
        p0 = transl_item(p0, x2[x4], &x5);
        x3[x4] = x5;
        x4 = x4 + 1;
    };

    (% save values of special purpose registers %);
    if (x1 > num_normal_regs()) {
	x4 = num_normal_regs();
	while (x4 < x1) {
	    p0 = ls_cons(mkinst(INST_PUSHL, NULL, get_physical_reg(x4)), p0);
	    x4 = x4 + 1;
	};
    };

    x4 = 0;
    while (x4 < x1) {
        p0 = ls_cons(mkinst(INST_MOVL, get_physical_reg(x4), x3[x4]), p0);
        x4 = x4 + 1;
    };
    x6 = mkinst(INST_INT, NULL, mktup2(OPD_INTEGER, 128));
    x6[INST_ARG] = x1;

    p0 = ls_cons(x6, p0);

    (% restore special purpose registers %);
    if (x1 > num_normal_regs()) {
	x4 = num_normal_regs();
	while (x4 < x1) {
	    p0 = ls_cons(mkinst(INST_POPL, get_physical_reg(x4), NULL), p0);
	    x4 = x4 + 1;
	};
    };
    return p0;
};

(% p0: output tcode, p1: item, p2: pointer to store p1's value  %);
transl_item: (p0, p1, p2) {
    allocate(2);
    x0 = transl_funcs[p1[0]];
    return x0(p0, p1, p2);
};

transl_extfuncs: [
    not_reachable, not_implemented, not_implemented, not_implemented, not_implemented,
    not_implemented, not_implemented, not_implemented, transl_extdecl, not_implemented,
    not_implemented, not_implemented, not_implemented, not_implemented, not_implemented,
    transl_export, not_implemented, not_implemented
];

transl_fundecl: (p0) {
    allocate(7);

    reset_proc();

    x0 = mangle(p0[1], get_ident_name(p0[2]));
    x1 = p0[3]; (% lambda %);

    x2 = x1[2]; (% argument %);
    x3 = x2[TUPLE_LENGTH];
    x4 = x2[TUPLE_ELEMENTS];
    x5 = 0;
    while (x5 < x3) {
        set_operand(x4[x5], create_pseudo());
        x5 = x5 + 1;
    };

    x6 = ls_reverse(transl_code(NULL, x1[3]));
    x5 = 0;
    while (x5 < x3) {
        x6 = ls_cons(mkinst(INST_MOVL, get_operand(x4[x5]), get_arg(x5)), x6);
        x5 = x5 + 1;
    };

    x6 = mktup5(TCODE_FUNC, x0, x1[2], x6, FALSE);

    (% liveness analysis %);
    liveness(x6);

    (% allocate registers %);
    regalloc(x6);

    return x6;
};

transl_static_data: (p0) {
    allocate(4);
    if (p0[0] == NODE_INTEGER) {
        if (p0[2] == 8) { return mktup2(DATA_CHAR, p0[3]); };
        if (p0[2] == 32) { return mktup2(DATA_INT, p0[3]); };
        not_reachable();
    };
    if (p0[0] == NODE_ARRAY) {
        x0 = p0[2]; (% length %);
        x1 = p0[3]; (% elements %);
        x2 = memalloc(4*x0); (% new elements %);
        x3 = 0;
        while (x3 < x0) {
            x2[x3] = transl_static_data(x1[x3]);
            x3 = x3 + 1;
        };
        return mktup3(DATA_ARRAY, x0, x2);
    };
    if (p0[0] == NODE_TUPLE) {
        x0 = p0[2]; (% length %);
        x1 = p0[3]; (% elements %);
        x2 = memalloc(4*x0); (% new elements %);
        x3 = 0;
        while (x3 < x0) {
            x2[x3] = transl_static_data(x1[x3]);
            x3 = x3 + 1;
        };
        return mktup3(DATA_TUPLE, x0, x2);
    };
    if (p0[0] == NODE_STRING) {
        x0 = new_label();
        add_topdecl(mktup4(TCODE_DATA, x0, mktup2(DATA_STRING, p0[2]), FALSE));
        return mktup2(DATA_LABEL, x0);
    };
    not_implemented();
};

(% p0: item %);
transl_extdecl: (p0) {
    allocate(3);
    x0 = p0[1]; (% type %);
    (% generate label %);
    if (x0[0] == NODE_LAMBDA_T) {
        return transl_fundecl(p0, p0);
    };

    x1 = get_ident_name(p0[2]);

    set_operand(p0[2], mktup2(OPD_LABEL, x1));

    (% flatten nested static data and translate to tcode %);
    x2 = transl_static_data(p0[3]);

    return mktup4(TCODE_DATA, x1, x2, FALSE);
};

(% p0: item %);
transl_export: (p0) {
    allocate(1);
    x0 = transl_extitem(p0[1]);
    if (x0[0] == TCODE_DATA) {
        x0[3] = TRUE;
        return x0;
    };
    if (x0[0] == TCODE_FUNC) {
        x0[4] = TRUE;
        return x0;
    };
    fputs(stderr, "ERROR: invalid export directive\n");
    exit(1);
};

(% p0: item %);
transl_extitem: (p0) {
    allocate(1);
    x0 = transl_extfuncs[p0[0]];
    return x0(p0);
};

(% p0: program (item list) %);
tcodegen: (p0) {
    allocate(2);

    init_proc();

    vtable = mkvec(num_variable());
    topdecl = NULL;

    x0 = p0[1];
    x1 = NULL;
    while (x0 != NULL) {
        x1 = ls_cons(transl_extitem(ls_value(x0)), x1);
        x0 = ls_next(x0);
    };
    return ls_append(ls_reverse(x1), ls_reverse(topdecl));
};
